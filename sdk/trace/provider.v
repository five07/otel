module trace

import context
import os
import strconv
import five07.otel
import five07.otel.sdk.resource

// ProviderOptions set up a `TracerProvider`. What isn't given comes from the
// environment or the specification's defaults.
@[params]
pub struct ProviderOptions {
pub:
	// resource describes the app; by default `resource.default()`
	resource ?resource.Resource
	// sampler decides which spans are kept; by default from
	// `OTEL_TRACES_SAMPLER`, else `parent_based(always_on_sampler())`
	sampler ?Sampler
	// id_generator makes ids; by default a `RandomIdGenerator`
	id_generator ?IdGenerator
	// processors get the spans, in this order
	processors []SpanProcessor
	// limits bound each span; by default from the `OTEL_*_LIMIT` variables,
	// else 128 of each
	limits ?SpanLimits
}

// TracerProvider is the SDK's provider: it makes the tracers that libraries
// ask for, and sends their spans to its processors. An app builds one at its
// start and hands it to what it instruments.
@[heap]
pub struct TracerProvider {
	resource     resource.Resource
	sampler      Sampler
	id_generator IdGenerator
	processors   []SpanProcessor
	limits       SpanLimits
mut:
	stopped shared bool
}

// TracerProvider.new builds a provider. It fails when the environment it reads
// is malformed, or when no secure seed for ids can be had.
pub fn TracerProvider.new(opts ProviderOptions) !&TracerProvider {
	return &TracerProvider{
		resource:     opts.resource or { resource.default()! }
		sampler:      opts.sampler or { sampler_from_env()! }
		id_generator: opts.id_generator or { IdGenerator(RandomIdGenerator.new()!) }
		processors:   opts.processors.clone()
		limits:       opts.limits or { limits_from_env()! }
	}
}

// tracer returns a tracer for the library named `name`; its spans carry the
// name and options as their instrumentation scope.
pub fn (p &TracerProvider) tracer(name string, opts otel.TracerOptions) otel.Tracer {
	return &Tracer{
		provider: p
		scope:    InstrumentationScope{
			name:       name
			version:    opts.version
			schema_url: opts.schema_url
			attributes: opts.attributes.clone()
		}
	}
}

// force_flush asks every processor to export what it holds, and returns when
// they have; the error lists each processor's.
pub fn (p &TracerProvider) force_flush() ! {
	mut errs := []string{}
	for processor in p.processors {
		processor.force_flush() or { errs << err.msg() }
	}
	if errs.len > 0 {
		return error(errs.join('; '))
	}
}

// shutdown flushes and stops every processor, in order, once; later calls do
// nothing. Afterwards tracers start spans that record nothing. The error lists
// each processor's.
pub fn (p &TracerProvider) shutdown() ! {
	first := lock p.stopped {
		was := p.stopped
		p.stopped = true
		!was
	}
	if !first {
		return
	}
	mut errs := []string{}
	for processor in p.processors {
		processor.shutdown() or { errs << err.msg() }
	}
	if errs.len > 0 {
		return error(errs.join('; '))
	}
}

fn (p &TracerProvider) is_stopped() bool {
	return rlock p.stopped {
		p.stopped
	}
}

fn (p &TracerProvider) end(span ReadOnlySpan) {
	for processor in p.processors {
		processor.on_end(span)
	}
}

// Tracer starts spans for one instrumentation scope.
@[heap]
pub struct Tracer {
	provider &TracerProvider
	scope    InstrumentationScope
}

// start starts a span: a child of the span in `ctx`, in its trace, or with
// `new_root` (or no span in `ctx`) the root of a new trace. The sampler
// decides whether it records; one that doesn't still carries its ids, so the
// trace goes on to the services it calls. After the provider's `shutdown`,
// every span records nothing.
pub fn (t &Tracer) start(ctx context.Context, name string, opts otel.SpanStartOptions) (context.Context, otel.Span) {
	p := t.provider
	parent_span := if opts.new_root {
		otel.Span(otel.NoopSpan{})
	} else {
		otel.span_from_context(ctx)
	}
	parent := parent_span.span_context()
	// a parent recording in this process lends its clock anchor, so the trace's
	// spans share one timeline
	anchor := if parent_span is RecordingSpan { ?Anchor(parent_span.anchor) } else { none }
	trace_id := if parent.is_valid() { parent.trace_id } else { p.id_generator.new_trace_id() }
	result := p.sampler.should_sample(SamplingParameters{
		parent:     parent
		trace_id:   trace_id
		name:       name
		kind:       opts.kind
		attributes: opts.attributes
		links:      opts.links
	})
	sc := otel.SpanContext{
		trace_id: trace_id
		span_id:  p.id_generator.new_span_id()
		flags:    parent.flags.with_sampled(result.decision == .record_and_sample)
		state:    result.trace_state
	}
	if result.decision == .drop || p.is_stopped() {
		span := otel.NoopSpan{
			context: sc
		}
		return otel.context_with_span(ctx, span), span
	}
	mut attributes := opts.attributes.clone()
	attributes << result.attributes
	span := new_recording_span(SpanConfig{
		name:       name
		context:    sc
		parent:     parent
		kind:       opts.kind
		attributes: attributes
		links:      opts.links
		start:      opts.start
		anchor:     anchor
		scope:      t.scope
		resource:   p.resource
		limits:     p.limits
		on_end:     p.end
	})
	for processor in p.processors {
		processor.on_start(ctx, span)
	}
	return otel.context_with_span(ctx, span), span
}

// limits_from_env reads the span limits the environment sets, the rest at
// their defaults: `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT` (else
// `OTEL_ATTRIBUTE_COUNT_LIMIT`), `OTEL_SPAN_EVENT_COUNT_LIMIT`,
// `OTEL_SPAN_LINK_COUNT_LIMIT`, `OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT` and
// `OTEL_LINK_ATTRIBUTE_COUNT_LIMIT`. A value that isn't a whole number from 0
// up is an error.
fn limits_from_env() !SpanLimits {
	d := SpanLimits{}
	general := env_limit('OTEL_ATTRIBUTE_COUNT_LIMIT', d.attribute_count)!
	return SpanLimits{
		attribute_count:      env_limit('OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT', general)!
		event_count:          env_limit('OTEL_SPAN_EVENT_COUNT_LIMIT', d.event_count)!
		link_count:           env_limit('OTEL_SPAN_LINK_COUNT_LIMIT', d.link_count)!
		attributes_per_event: env_limit('OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT', d.attributes_per_event)!
		attributes_per_link:  env_limit('OTEL_LINK_ATTRIBUTE_COUNT_LIMIT', d.attributes_per_link)!
	}
}

fn env_limit(name string, default_value int) !int {
	value := os.getenv(name).trim_space()
	if value == '' {
		return default_value
	}
	n := strconv.atoi(value) or { return error('${name}: `${value}` is not a whole number') }
	if n < 0 {
		return error('${name}: `${value}` is below 0')
	}
	return n
}

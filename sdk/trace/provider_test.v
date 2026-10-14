module trace

import context
import os
import time
import five07.otel
import five07.otel.sdk.resource

// Collector is a processor that keeps the names of the spans it sees start,
// and the spans it sees end.
@[heap]
struct Collector {
mut:
	started shared []string
	ended   shared []ReadOnlySpan
}

fn (c &Collector) on_start(parent context.Context, span &RecordingSpan) {
	lock c.started {
		c.started << span.read_only().name
	}
}

fn (c &Collector) on_end(span ReadOnlySpan) {
	lock c.ended {
		c.ended << span
	}
}

fn (c &Collector) force_flush() ! {}

fn (c &Collector) shutdown() ! {}

fn (c &Collector) started() []string {
	return rlock c.started {
		c.started.clone()
	}
}

fn (c &Collector) ended() []ReadOnlySpan {
	return rlock c.ended {
		c.ended.clone()
	}
}

// FixedSampler always decides the same, adding an attribute and a trace state
// entry, to show the tracer uses what a sampler returns.
struct FixedSampler {
	decision SamplingDecision
}

fn (s FixedSampler) should_sample(p SamplingParameters) SamplingResult {
	return SamplingResult{
		decision:    s.decision
		attributes:  [otel.string_attr('sampler', 'fixed')]
		trace_state: p.parent.state.insert('fixed', 'yes') or { panic(err) }
	}
}

fn (s FixedSampler) description() string {
	return 'FixedSampler'
}

fn new_provider(c &Collector, sampler ?Sampler) &TracerProvider {
	return TracerProvider.new(
		resource:     resource.Resource.new([otel.string_attr('service.name', 'test')], '')
		sampler:      sampler
		id_generator: SequentialIdGenerator.new()
		processors:   [c]
		limits:       SpanLimits{}
	) or { panic(err) }
}

fn test_a_root_and_its_child() {
	c := &Collector{}
	p := new_provider(c, none)
	tracer := p.tracer('five07.vgraph', version: '0.1.0')
	ctx, root := tracer.start(context.background(), 'GET /users', kind: .server)
	_, child := tracer.start(ctx, 'SELECT users', kind: .client)
	assert root.is_recording()
	assert root.span_context().trace_id.hex() == '00000000000000000000000000000001'
	assert root.span_context().span_id.hex() == '0000000000000001'
	assert root.span_context().is_sampled()
	assert child.span_context().trace_id == root.span_context().trace_id
	assert child.span_context().span_id.hex() == '0000000000000002'
	child.end()
	root.end()
	assert c.started() == ['GET /users', 'SELECT users']
	ended := c.ended()
	assert ended.map(it.name) == ['SELECT users', 'GET /users']
	assert ended[0].parent == root.span_context()
	assert !ended[1].parent.is_valid()
	assert ended[0].kind == .client
	assert ended[1].scope.name == 'five07.vgraph'
	assert ended[1].scope.version == '0.1.0'
	assert ended[1].resource.get('service.name')? as string == 'test'
}

fn test_a_remote_parent_keeps_its_trace_flags_and_state() {
	c := &Collector{}
	p := new_provider(c, none)
	remote := otel.SpanContext{
		trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
		span_id:  otel.SpanId.from_hex('00f067aa0ba902b7')!
		flags:    otel.TraceFlags{}.with_sampled(true)
		state:    otel.TraceState{}.insert('congo', 't61rcWkgMzE')!
		remote:   true
	}
	ctx := otel.context_with_span_context(context.background(), remote)
	_, span := p.tracer('lib').start(ctx, 'handle')
	sc := span.span_context()
	assert sc.trace_id == remote.trace_id
	assert sc.span_id != remote.span_id
	assert sc.is_sampled()
	assert sc.state.get('congo')? == 't61rcWkgMzE'
	assert !sc.remote
	span.end()
	assert c.ended()[0].parent == remote
	assert c.ended()[0].parent.remote
}

fn test_new_root_ignores_the_parent() {
	c := &Collector{}
	p := new_provider(c, none)
	tracer := p.tracer('lib')
	ctx, root := tracer.start(context.background(), 'a')
	_, other := tracer.start(ctx, 'b', new_root: true)
	assert other.span_context().trace_id != root.span_context().trace_id
	other.end()
	assert !c.ended()[0].parent.is_valid()
}

fn test_a_dropped_span_records_nothing_but_carries_the_trace() {
	c := &Collector{}
	p := new_provider(c, FixedSampler{
		decision: .drop
	})
	tracer := p.tracer('lib')
	ctx, span := tracer.start(context.background(), 'a')
	assert !span.is_recording()
	sc := span.span_context()
	assert sc.is_valid()
	assert !sc.is_sampled()
	assert sc.state.get('fixed')? == 'yes'
	_, child := tracer.start(ctx, 'b')
	assert child.span_context().trace_id == sc.trace_id
	child.end()
	span.end()
	assert c.started().len == 0
	assert c.ended().len == 0
}

fn test_record_only_records_but_does_not_sample() {
	c := &Collector{}
	p := new_provider(c, FixedSampler{
		decision: .record_only
	})
	_, span := p.tracer('lib').start(context.background(), 'a',
		attributes: [otel.string_attr('k', 'v')]
	)
	assert span.is_recording()
	assert !span.span_context().is_sampled()
	span.end()
	r := c.ended()[0]
	assert r.attributes == [otel.string_attr('k', 'v'), otel.string_attr('sampler', 'fixed')]
}

fn test_start_options_reach_the_span() {
	c := &Collector{}
	p := new_provider(c, none)
	at := time.unix(1_700_000_000)
	link := otel.Link{
		span_context: otel.SpanContext{
			trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
			span_id:  otel.SpanId.from_hex('00f067aa0ba902b7')!
		}
	}
	_, span := p.tracer('lib').start(context.background(), 'batch',
		kind:  .consumer
		start: at
		links: [link]
	)
	span.end(end: time.unix(1_700_000_001))
	r := c.ended()[0]
	assert r.kind == .consumer
	assert r.start_ns == at.unix_nano()
	assert r.end_ns - r.start_ns == 1_000_000_000
	assert r.links[0].span_context == link.span_context
}

fn test_the_span_is_in_the_returned_context() {
	c := &Collector{}
	p := new_provider(c, none)
	ctx, span := p.tracer('lib').start(context.background(), 'a')
	assert otel.span_from_context(ctx).span_context() == span.span_context()
}

fn test_it_is_an_otel_tracer_provider() {
	c := &Collector{}
	provider := otel.TracerProvider(new_provider(c, none))
	_, span := provider.tracer('lib').start(context.background(), 'a')
	span.end()
	assert c.ended().len == 1
}

fn test_defaults_build() {
	os.unsetenv('OTEL_RESOURCE_ATTRIBUTES')
	p := TracerProvider.new()!
	_, span := p.tracer('lib').start(context.background(), 'a')
	assert span.is_recording()
	assert span.span_context().is_valid()
	assert p.limits == SpanLimits{}
}

fn test_span_limits_from_the_environment() {
	names := ['OTEL_ATTRIBUTE_COUNT_LIMIT', 'OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT',
		'OTEL_SPAN_EVENT_COUNT_LIMIT', 'OTEL_SPAN_LINK_COUNT_LIMIT', 'OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT',
		'OTEL_LINK_ATTRIBUTE_COUNT_LIMIT']
	for name in names {
		os.unsetenv(name)
	}
	unset, no_warnings := limits_from_env()
	assert unset == SpanLimits{}
	assert no_warnings.len == 0
	os.setenv('OTEL_ATTRIBUTE_COUNT_LIMIT', '10', true)
	general, _ := limits_from_env()
	assert general.attribute_count == 10
	// the span's own variable wins over the general one
	os.setenv('OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT', ' 20 ', true)
	os.setenv('OTEL_SPAN_EVENT_COUNT_LIMIT', '0', true)
	os.setenv('OTEL_SPAN_LINK_COUNT_LIMIT', '3', true)
	os.setenv('OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT', '4', true)
	os.setenv('OTEL_LINK_ATTRIBUTE_COUNT_LIMIT', '5', true)
	all, _ := limits_from_env()
	assert all == SpanLimits{
		attribute_count:      20
		event_count:          0
		link_count:           3
		attributes_per_event: 4
		attributes_per_link:  5
	}
	// a bad value keeps the default, with a warning
	for bad, want in {
		'many': 'OTEL_SPAN_LINK_COUNT_LIMIT: `many` is not a whole number; using 128'
		'-1':   'OTEL_SPAN_LINK_COUNT_LIMIT: `-1` is below 0; using 128'
		'1.5':  'OTEL_SPAN_LINK_COUNT_LIMIT: `1.5` is not a whole number; using 128'
	} {
		os.setenv('OTEL_SPAN_LINK_COUNT_LIMIT', bad, true)
		limits, warnings := limits_from_env()
		assert limits.link_count == 128
		assert warnings == [want]
	}
	// and the provider still builds
	_ := TracerProvider.new()!
	for name in names {
		os.unsetenv(name)
	}
}

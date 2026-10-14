module trace

import context
import five07.otel
import five07.otel.sdk.resource

fn provider_with(processors []SpanProcessor, sampler Sampler) &TracerProvider {
	return TracerProvider.new(
		resource:     resource.Resource.new([], '')
		sampler:      sampler
		id_generator: SequentialIdGenerator.new()
		processors:   processors
		limits:       SpanLimits{}
	) or { panic(err) }
}

fn test_sampled_spans_are_exported_as_they_end() {
	exporter := InMemoryExporter.new()
	p := provider_with([SimpleSpanProcessor.new(exporter)], always_on_sampler())
	tracer := p.tracer('lib')
	ctx, root := tracer.start(context.background(), 'root')
	_, child := tracer.start(ctx, 'child')
	assert exporter.spans().len == 0
	child.end()
	assert exporter.spans().map(it.name) == ['child']
	root.end()
	assert exporter.spans().map(it.name) == ['child', 'root']
	exporter.reset()
	assert exporter.spans().len == 0
}

// RecordOnly records every span without sampling it.
struct RecordOnly {}

fn (s RecordOnly) should_sample(p SamplingParameters) SamplingResult {
	return SamplingResult{
		decision: .record_only
	}
}

fn (s RecordOnly) description() string {
	return 'RecordOnly'
}

fn test_unsampled_spans_are_not_exported() {
	exporter := InMemoryExporter.new()
	p := provider_with([SimpleSpanProcessor.new(exporter)], RecordOnly{})
	_, span := p.tracer('lib').start(context.background(), 'a')
	assert span.is_recording()
	span.end()
	assert exporter.spans().len == 0

	off := InMemoryExporter.new()
	q := provider_with([SimpleSpanProcessor.new(off)], always_off_sampler())
	_, dropped := q.tracer('lib').start(context.background(), 'a')
	dropped.end()
	assert off.spans().len == 0
}

// Failing is an exporter that fails every export, and counts its shutdowns.
@[heap]
struct Failing {
mut:
	shutdowns shared int
}

fn (f &Failing) export(spans []ReadOnlySpan) ! {
	return error('collector unreachable')
}

fn (f &Failing) shutdown() ! {
	lock f.shutdowns {
		f.shutdowns++
	}
	return error('failing shut down')
}

@[heap]
struct Errors {
mut:
	msgs shared []string
}

fn test_export_errors_go_to_on_error() {
	errs := &Errors{}
	processor := SimpleSpanProcessor.new(&Failing{},
		on_error: fn [errs] (err IError) {
			lock errs.msgs {
				errs.msgs << err.msg()
			}
		}
	)
	p := provider_with([processor], always_on_sampler())
	_, span := p.tracer('lib').start(context.background(), 'a')
	span.end()
	assert rlock errs.msgs {
		errs.msgs.clone()
	} == ['collector unreachable']
}

fn test_shutdown_stops_everything_once() {
	exporter := InMemoryExporter.new()
	failing := &Failing{}
	p := provider_with([SimpleSpanProcessor.new(exporter), SimpleSpanProcessor.new(failing)],
		always_on_sampler())
	tracer := p.tracer('lib')
	_, before := tracer.start(context.background(), 'before')
	before.end()
	if _ := p.shutdown() {
		assert false, "the failing exporter's error was lost"
	} else {
		assert err.msg() == 'failing shut down'
	}
	// a second shutdown does nothing
	p.shutdown()!
	assert rlock failing.shutdowns {
		failing.shutdowns
	} == 1
	// spans started afterwards record nothing, but still carry the trace
	_, after := tracer.start(context.background(), 'after')
	assert !after.is_recording()
	assert after.span_context().is_valid()
	after.end()
	assert exporter.spans().map(it.name) == ['before']
	// and the exporter refuses more
	if _ := exporter.export([]) {
		assert false, 'a shut-down exporter took spans'
	}
}

fn test_a_span_ended_after_shutdown_is_not_exported() {
	exporter := InMemoryExporter.new()
	p := provider_with([SimpleSpanProcessor.new(exporter)], always_on_sampler())
	_, span := p.tracer('lib').start(context.background(), 'late')
	p.shutdown()!
	span.end()
	assert exporter.spans().len == 0
}

// Flushes counts force_flush and shutdown calls, and fails flushes when told to.
@[heap]
struct Flushes {
	fail bool
mut:
	count     shared int
	shutdowns shared int
}

fn (f &Flushes) on_start(parent context.Context, span &RecordingSpan) {}

fn (f &Flushes) on_end(span ReadOnlySpan) {}

fn (f &Flushes) force_flush() ! {
	lock f.count {
		f.count++
	}
	if f.fail {
		return error('flush failed')
	}
}

fn (f &Flushes) shutdown() ! {
	lock f.shutdowns {
		f.shutdowns++
	}
}

fn test_the_provider_shuts_each_processor_down_once() {
	f := &Flushes{}
	p := provider_with([f], always_on_sampler())
	p.shutdown()!
	p.shutdown()!
	assert rlock f.shutdowns {
		f.shutdowns
	} == 1
}

fn test_force_flush_reaches_every_processor() {
	a := &Flushes{}
	b := &Flushes{
		fail: true
	}
	p := provider_with([a, b, a], always_on_sampler())
	if _ := p.force_flush() {
		assert false, 'a failed flush was lost'
	} else {
		assert err.msg() == 'flush failed'
	}
	assert rlock a.count {
		a.count
	} == 2
	assert rlock b.count {
		b.count
	} == 1
	simple := provider_with([SimpleSpanProcessor.new(InMemoryExporter.new())], always_on_sampler())
	simple.force_flush()!
}

fn test_exports_from_many_threads_are_all_kept() {
	exporter := InMemoryExporter.new()
	p := provider_with([SimpleSpanProcessor.new(exporter)], always_on_sampler())
	tracer := p.tracer('lib')
	mut threads := []thread{}
	for _ in 0 .. 8 {
		threads << spawn fn (tracer otel.Tracer) {
			for _ in 0 .. 250 {
				_, span := tracer.start(context.background(), 'work')
				span.end()
			}
		}(tracer)
	}
	threads.wait()
	spans := exporter.spans()
	assert spans.len == 2000
	mut ids := map[string]bool{}
	for s in spans {
		ids[s.span_context.span_id.hex()] = true
	}
	assert ids.len == 2000
}

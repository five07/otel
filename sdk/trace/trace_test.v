module trace

// Tests through the whole SDK, wired as an app wires it: a provider with the
// default parent-based sampler, a simple processor and an in-memory exporter.
import context
import time
import five07.otel
import five07.otel.sdk.resource

struct Setup {
	provider &TracerProvider
	exporter &InMemoryExporter
}

fn setup(sampler Sampler, ids IdGenerator) Setup {
	exporter := InMemoryExporter.new()
	provider := TracerProvider.new(
		resource:     resource.Resource.new([otel.string_attr('service.name', 'blog')], '')
		sampler:      sampler
		id_generator: ids
		processors:   [SimpleSpanProcessor.new(exporter)]
		limits:       SpanLimits{}
	) or { panic(err) }
	return Setup{provider, exporter}
}

fn by_name(spans []ReadOnlySpan) map[string]ReadOnlySpan {
	mut m := map[string]ReadOnlySpan{}
	for s in spans {
		m[s.name] = s
	}
	return m
}

fn remote(sampled bool) otel.SpanContext {
	return otel.SpanContext{
		trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736') or { panic(err) }
		span_id:  otel.SpanId.from_hex('00f067aa0ba902b7') or { panic(err) }
		flags:    otel.TraceFlags{}.with_sampled(sampled)
		state:    otel.TraceState{}.insert('congo', 't61rcWkgMzE') or { panic(err) }
		remote:   true
	}
}

// three_levels runs a request, a resolver in it and a statement in that, as
// vgraph will.
fn three_levels(tracer otel.Tracer, ctx context.Context) {
	ctx1, request := tracer.start(ctx, 'query Posts', kind: .server)
	ctx2, resolver := tracer.start(ctx1, 'Post.author')
	_, statement := tracer.start(ctx2, 'SELECT users', kind: .client)
	statement.end()
	resolver.end()
	request.end()
}

fn test_three_levels_in_one_trace() {
	t := setup(parent_based(always_on_sampler()), SequentialIdGenerator.new())
	three_levels(t.provider.tracer('five07.vgraph', version: '0.1.0'), context.background())
	spans := t.exporter.spans()
	// exported as they end: the innermost first
	assert spans.map(it.name) == ['SELECT users', 'Post.author', 'query Posts']
	s := by_name(spans)
	request, resolver, statement := s['query Posts'], s['Post.author'], s['SELECT users']
	for span in spans {
		assert span.span_context.trace_id.hex() == '00000000000000000000000000000001'
		assert span.span_context.is_sampled()
		assert span.scope.name == 'five07.vgraph'
		assert span.resource.get('service.name')? as string == 'blog'
		assert span.end_ns >= span.start_ns
	}
	assert request.span_context.span_id.hex() == '0000000000000001'
	assert resolver.span_context.span_id.hex() == '0000000000000002'
	assert statement.span_context.span_id.hex() == '0000000000000003'
	assert !request.parent.is_valid()
	assert resolver.parent == request.span_context
	assert statement.parent == resolver.span_context
	assert request.kind == .server
	assert resolver.kind == .internal
	assert statement.kind == .client
	// each span lies within its parent's time
	assert request.start_ns <= resolver.start_ns && resolver.end_ns <= request.end_ns
	assert resolver.start_ns <= statement.start_ns && statement.end_ns <= resolver.end_ns
}

fn test_spans_from_the_same_context_are_siblings() {
	t := setup(parent_based(always_on_sampler()), SequentialIdGenerator.new())
	tracer := t.provider.tracer('lib')
	ctx, root := tracer.start(context.background(), 'root')
	_, a := tracer.start(ctx, 'a')
	_, b := tracer.start(ctx, 'b')
	b.end()
	a.end()
	root.end()
	s := by_name(t.exporter.spans())
	assert s['a'].parent == s['root'].span_context
	assert s['b'].parent == s['root'].span_context
}

fn test_a_sampled_remote_parent_continues_its_trace() {
	t := setup(parent_based(always_off_sampler()), SequentialIdGenerator.new())
	ctx := otel.context_with_span_context(context.background(), remote(true))
	three_levels(t.provider.tracer('lib'), ctx)
	s := by_name(t.exporter.spans())
	// the root sampler (off) isn't asked: the parent was sampled
	assert s.len == 3
	assert s['query Posts'].parent == remote(true)
	for _, span in s {
		assert span.span_context.trace_id == remote(true).trace_id
		assert span.span_context.state.get('congo')? == 't61rcWkgMzE'
	}
}

fn test_an_unsampled_remote_parent_is_followed_and_still_propagated() {
	t := setup(parent_based(always_on_sampler()), SequentialIdGenerator.new())
	tracer := t.provider.tracer('lib')
	ctx := otel.context_with_span_context(context.background(), remote(false))
	ctx1, request := tracer.start(ctx, 'request')
	ctx2, resolver := tracer.start(ctx1, 'resolver')
	_, statement := tracer.start(ctx2, 'statement')
	for span in [request, resolver, statement] {
		assert !span.is_recording()
		sc := span.span_context()
		// what an outgoing call would carry: the caller's trace, not sampled
		assert sc.trace_id == remote(false).trace_id
		assert !sc.is_sampled()
		assert sc.state.get('congo')? == 't61rcWkgMzE'
		span.end()
	}
	assert t.exporter.spans().len == 0
}

fn test_a_ratio_keeps_or_drops_whole_traces() {
	t := setup(parent_based(trace_id_ratio_based(0.5)), RandomIdGenerator.with_seed([
		u32(3),
		1,
		4,
		1,
	]))
	tracer := t.provider.tracer('lib')
	for _ in 0 .. 200 {
		three_levels(tracer, context.background())
	}
	mut per_trace := map[string]int{}
	for span in t.exporter.spans() {
		per_trace[span.span_context.trace_id.hex()]++
	}
	// about half the traces, each with all three of its spans
	assert per_trace.len > 70 && per_trace.len < 130
	for _, n in per_trace {
		assert n == 3
	}
}

fn test_explicit_times_place_a_statement_inside_its_request() {
	t := setup(parent_based(always_on_sampler()), SequentialIdGenerator.new())
	tracer := t.provider.tracer('lib')
	ctx, request := tracer.start(context.background(), 'request')
	// an explicit time comes from the wall clock, coarser than the spans' own
	// timeline (a microsecond on macOS), so it is taken a little after the start
	time.sleep(time.millisecond)
	began := time.now()
	time.sleep(2 * time.millisecond)
	_, statement := tracer.start(ctx, 'statement', start: began)
	statement.end()
	request.end()
	s := by_name(t.exporter.spans())
	assert s['statement'].start_ns == began.unix_nano()
	assert s['statement'].end_ns - s['statement'].start_ns >= 2_000_000
	assert s['request'].start_ns <= s['statement'].start_ns
}

fn test_a_layer_with_no_provider_keeps_the_trace_together() {
	// the app traces; a library in the middle was given no provider
	t := setup(parent_based(always_on_sampler()), SequentialIdGenerator.new())
	app := t.provider.tracer('app')
	library := otel.noop_tracer_provider().tracer('library')
	ctx1, request := app.start(context.background(), 'request')
	ctx2, middle := library.start(ctx1, 'middle')
	_, statement := app.start(ctx2, 'statement')
	statement.end()
	middle.end()
	request.end()
	s := by_name(t.exporter.spans())
	assert s.len == 2
	// the middle span records nothing, so the statement's parent is the request
	assert s['statement'].parent == s['request'].span_context
	assert s['statement'].span_context.trace_id == s['request'].span_context.trace_id
}

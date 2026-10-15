module otel

import context

fn remote_parent() SpanContext {
	return SpanContext{
		trace_id: TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736') or { panic(err) }
		span_id:  SpanId.from_hex('00f067aa0ba902b7') or { panic(err) }
		flags:    TraceFlags{}.with_sampled(true)
		remote:   true
	}
}

fn test_no_span_gives_a_noop_span() {
	span := span_from_context(context.background())
	assert !span.is_recording()
	assert !span.span_context().is_valid()
	assert span is NoopSpan
}

fn test_a_span_goes_in_and_comes_out() {
	sc := remote_parent()
	ctx := context_with_span(context.background(), NoopSpan{
		context: sc
	})
	got := span_from_context(ctx)
	assert got is NoopSpan
	assert got.span_context() == sc
}

fn test_the_nearest_span_wins_and_other_values_pass_through() {
	outer := remote_parent()
	inner := SpanContext{
		trace_id: outer.trace_id
		span_id:  SpanId.from_hex('b7ad6b7169203331')!
	}
	ctx1 := context_with_span_context(context.background(), outer)
	ctx2 := context.with_value(ctx1, 'app.user', 'u-1')
	ctx3 := context_with_span_context(ctx2, inner)
	assert span_from_context(ctx1).span_context() == outer
	assert span_from_context(ctx2).span_context() == outer
	assert span_from_context(ctx3).span_context() == inner
	user := ctx3.value('app.user') or { panic('the app value was lost') }
	assert user is string
	assert user as string == 'u-1'
}

fn test_a_string_key_does_not_find_the_span() {
	ctx := context_with_span_context(context.background(), remote_parent())
	for key in ['span', 'otel.span', 'five07.otel.span'] {
		if _ := ctx.value(key) {
			assert false, 'the span was found under `${key}`'
		}
	}
}

fn test_a_noop_tracer_passes_the_remote_parent_on() {
	parent := remote_parent()
	ctx := context_with_span_context(context.background(), parent)
	tracer := noop_tracer_provider().tracer('lib')
	ctx2, span := tracer.start(ctx, 'child')
	assert !span.is_recording()
	assert span.span_context() == parent
	// and to the next level down
	_, grandchild := tracer.start(ctx2, 'grandchild')
	assert grandchild.span_context() == parent
}

fn test_a_noop_new_root_drops_the_parent() {
	ctx := context_with_span_context(context.background(), remote_parent())
	_, span := noop_tracer_provider().tracer('lib').start(ctx, 'root', new_root: true)
	assert !span.span_context().is_valid()
}

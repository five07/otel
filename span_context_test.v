module otel

fn test_trace_flags_sampled_bit() {
	f := TraceFlags{}
	assert !f.is_sampled()
	assert f.hex() == '00'
	s := f.with_sampled(true)
	assert s.is_sampled()
	assert s.hex() == '01'
	assert '${s}' == '01'
	assert !s.with_sampled(false).is_sampled()
}

fn test_trace_flags_keep_unknown_bits() {
	// bits from a later version of the spec pass through untouched
	f := TraceFlags{
		bits: 0x82
	}
	assert !f.is_sampled()
	assert f.with_sampled(true).bits == 0x83
	assert f.with_sampled(true).with_sampled(false).bits == 0x82
	assert f.hex() == '82'
}

fn test_span_context_validity() {
	trace_id := TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
	span_id := SpanId.from_hex('00f067aa0ba902b7')!
	assert !SpanContext{}.is_valid()
	assert !SpanContext{
		trace_id: trace_id
	}.is_valid()
	assert !SpanContext{
		span_id: span_id
	}.is_valid()
	sc := SpanContext{
		trace_id: trace_id
		span_id:  span_id
		flags:    TraceFlags{}.with_sampled(true)
		remote:   true
	}
	assert sc.is_valid()
	assert sc.is_sampled()
	assert sc.remote
	assert sc.state.len() == 0
}

fn test_span_contexts_compare_by_value() {
	trace_id := TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
	span_id := SpanId.from_hex('00f067aa0ba902b7')!
	state := TraceState{}.insert('congo', 't61rcWkgMzE')!
	a := SpanContext{
		trace_id: trace_id
		span_id:  span_id
		state:    state
	}
	b := SpanContext{
		trace_id: trace_id
		span_id:  span_id
		state:    TraceState{}.insert('congo', 't61rcWkgMzE')!
	}
	c := SpanContext{
		trace_id: trace_id
		span_id:  span_id
		state:    state.insert('rojo', '00f067aa0ba902b7')!
	}
	assert a == b
	assert a != c
}

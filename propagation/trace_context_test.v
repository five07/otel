module propagation

import context
import five07.otel

const trace_hex = '4bf92f3577b34da6a3ce929d0e0e4736'
const span_hex = '00f067aa0ba902b7'

fn extracted(headers map[string]string) otel.SpanContext {
	ctx := TraceContext{}.extract(context.background(), MapCarrier.new(headers))
	return otel.span_from_context(ctx).span_context()
}

fn test_extract_reads_a_valid_traceparent() {
	sc := extracted({
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'tracestate':  'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE'
	})
	assert sc.is_valid()
	assert sc.trace_id.hex() == trace_hex
	assert sc.span_id.hex() == span_hex
	assert sc.is_sampled()
	assert sc.remote
	assert sc.state.str() == 'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE'
	assert !extracted({
		'traceparent': '00-${trace_hex}-${span_hex}-00'
	}).is_sampled()
}

fn test_header_names_are_case_insensitive() {
	assert extracted({
		'TraceParent': '00-${trace_hex}-${span_hex}-01'
	}).is_valid()
}

fn test_the_w3c_cases() {
	valid := [
		'00-${trace_hex}-${span_hex}-01',
		' 00-${trace_hex}-${span_hex}-01\t',
		// a later version may add fields after a `-`
		'cc-${trace_hex}-${span_hex}-01',
		'cc-${trace_hex}-${span_hex}-01-what-the-future-will-be-like',
		// unknown flag bits are allowed (and dropped)
		'00-${trace_hex}-${span_hex}-09',
	]
	for h in valid {
		assert extracted({
			'traceparent': h
		}).is_valid(), '`${h}` should be read'
	}
	invalid := [
		'',
		'ff-${trace_hex}-${span_hex}-01',
		'0g-${trace_hex}-${span_hex}-01',
		'00-${trace_hex.to_upper()}-${span_hex}-01',
		'00-${trace_hex}-${span_hex.to_upper()}-01',
		'00-00000000000000000000000000000000-${span_hex}-01',
		'00-${trace_hex}-0000000000000000-01',
		'00-${trace_hex}-${span_hex}-0g',
		'00-${trace_hex}-${span_hex}-01-extra',
		'00-${trace_hex[1..]}-${span_hex}-01',
		'00-${trace_hex}-${span_hex}0-01',
		'00_${trace_hex}_${span_hex}_01',
		'cc-${trace_hex}-${span_hex}-01x',
		'00-${trace_hex}-${span_hex}',
	]
	for h in invalid {
		assert !extracted({
			'traceparent': h
		}).is_valid(), '`${h}` should not be read'
	}
}

fn test_only_the_sampled_flag_is_kept() {
	assert extracted({
		'traceparent': '00-${trace_hex}-${span_hex}-09'
	}).flags.bits == 0x01
}

fn test_a_bad_tracestate_is_dropped_alone() {
	sc := extracted({
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'tracestate':  'A=1'
	})
	assert sc.is_valid()
	assert sc.state.len() == 0
}

fn test_a_missing_or_bad_traceparent_leaves_the_context_alone() {
	ctx := context.background()
	assert TraceContext{}.extract(ctx, MapCarrier.new({})) == ctx
	assert TraceContext{}.extract(ctx, MapCarrier.new({
		'traceparent': 'garbage'
		'tracestate':  'a=1'
	})) == ctx
}

fn test_inject_writes_the_current_span() {
	sc := otel.SpanContext{
		trace_id: otel.TraceId.from_hex(trace_hex)!
		span_id:  otel.SpanId.from_hex(span_hex)!
		flags:    otel.TraceFlags{
			bits: 0x09
		}
		state:    otel.TraceState{}.insert('congo', 't61rcWkgMzE')!
	}
	ctx := otel.context_with_span_context(context.background(), sc)
	mut carrier := MapCarrier.new({})
	TraceContext{}.inject(ctx, mut carrier)
	assert carrier.to_map() == {
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'tracestate':  'congo=t61rcWkgMzE'
	}
}

fn test_inject_writes_nothing_without_a_valid_span() {
	mut carrier := MapCarrier.new({})
	TraceContext{}.inject(context.background(), mut carrier)
	unsampled := otel.context_with_span_context(context.background(), otel.SpanContext{
		trace_id: otel.TraceId.from_hex(trace_hex)!
		span_id:  otel.SpanId.from_hex(span_hex)!
	})
	assert carrier.keys().len == 0
	// a valid span that isn't sampled still goes out, flagged `00`, with no
	// tracestate when it has none
	TraceContext{}.inject(unsampled, mut carrier)
	assert carrier.to_map() == {
		'traceparent': '00-${trace_hex}-${span_hex}-00'
	}
}

fn test_a_round_trip_through_a_service() {
	// a request comes in, a span continues it, a call goes out
	incoming := MapCarrier.new({
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'tracestate':  'congo=t61rcWkgMzE'
	})
	ctx := TraceContext{}.extract(context.background(), incoming)
	ctx2, span := otel.noop_tracer_provider().tracer('lib').start(ctx, 'handle')
	mut outgoing := MapCarrier.new({})
	TraceContext{}.inject(ctx2, mut outgoing)
	assert outgoing.get('traceparent')? == '00-${trace_hex}-${span_hex}-01'
	assert outgoing.get('tracestate')? == 'congo=t61rcWkgMzE'
	span.end()
}

fn test_a_getter_carrier() {
	headers := {
		'Traceparent': '00-${trace_hex}-${span_hex}-01'
	}
	carrier := GetterCarrier{
		get_fn: fn [headers] (key string) ?string {
			for k, v in headers {
				if k.to_lower() == key {
					return v
				}
			}
			return none
		}
	}
	ctx := TraceContext{}.extract(context.background(), carrier)
	assert otel.span_from_context(ctx).span_context().trace_id.hex() == trace_hex
}

fn test_fields() {
	assert TraceContext{}.fields() == ['traceparent', 'tracestate']
}

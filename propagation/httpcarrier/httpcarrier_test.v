module httpcarrier

import context
import net.http
import five07.otel
import five07.otel.propagation

const traceparent = '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'

fn test_extracts_from_a_request_header_in_any_case() {
	header := http.new_custom_header_from_map({
		'TraceParent': traceparent
	})!
	ctx := propagation.default_propagator().extract(context.background(), new(header))
	sc := otel.span_from_context(ctx).span_context()
	assert sc.is_valid()
	assert sc.remote
	assert sc.trace_id.hex() == '4bf92f3577b34da6a3ce929d0e0e4736'
}

fn test_injects_into_a_header_to_send() {
	header := http.new_custom_header_from_map({
		'TraceParent': traceparent
	})!
	ctx := propagation.default_propagator().extract(context.background(), new(header))
	mut out := new(http.new_header())
	propagation.TraceContext{}.inject(ctx, mut out)
	assert out.header.get_custom('traceparent')? == traceparent
	assert out.keys() == ['traceparent']
	// set replaces
	out.set('traceparent', 'x')
	assert out.header.custom_values('traceparent') == ['x']
}

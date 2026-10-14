module otel

import time

// start_options and end_options stand in for `Tracer.start` and `Span.end`,
// to show how a caller passes the options.
fn start_options(name string, opts SpanStartOptions) SpanStartOptions {
	return opts
}

fn end_options(opts EndOptions) EndOptions {
	return opts
}

fn test_defaults() {
	assert int(SpanKind.internal) == 0
	assert Status{}.code == .unset
	assert Status{}.description == ''
	o := start_options('a')
	assert o.kind == .internal
	assert o.attributes.len == 0
	assert o.links.len == 0
	assert o.start == none
	assert !o.new_root
	assert end_options().end == none
}

fn test_start_options_are_named_arguments() {
	at := time.unix(1_700_000_000)
	o := start_options('GET /users',
		kind:       .server
		attributes: [string_attr('http.request.method', 'GET')]
		start:      at
		new_root:   true
	)
	assert o.kind == .server
	assert o.attributes == [string_attr('http.request.method', 'GET')]
	assert o.start? == at
	assert o.new_root
}

fn test_end_time() {
	at := time.unix(1_700_000_001)
	assert end_options(end: at).end? == at
}

fn test_links_carry_a_span_context_and_attributes() {
	sc := SpanContext{
		trace_id: TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
		span_id:  SpanId.from_hex('00f067aa0ba902b7')!
	}
	o := start_options('batch',
		links: [Link{
			span_context: sc
			attributes:   [int_attr('messaging.batch.index', 0)]
		}]
	)
	assert o.links.len == 1
	assert o.links[0].span_context == sc
	assert o.links[0].attributes[0].key == 'messaging.batch.index'
}

fn test_status_codes_are_ordered_as_in_otlp() {
	// OTLP numbers them unset 0, ok 1, error 2; the exporter relies on it
	assert int(StatusCode.unset) == 0
	assert int(StatusCode.ok) == 1
	assert int(StatusCode.error) == 2
	s := Status{
		code:        .error
		description: 'timed out'
	}
	assert s.code == .error
}

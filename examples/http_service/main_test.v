module main

import net.http
import time
import five07.otel
import five07.otel.sdk.trace

// start serves a new app on a free port, its spans kept in memory, and
// returns its base URL and the exporter.
fn start() !(string, &trace.InMemoryExporter, &trace.TracerProvider) {
	exporter := trace.InMemoryExporter.new()
	provider := trace.TracerProvider.new(
		sampler:      trace.parent_based(trace.always_on_sampler())
		id_generator: trace.SequentialIdGenerator.new()
		processors:   [trace.SimpleSpanProcessor.new(exporter)]
	)!
	mut server := &http.Server{
		addr:                 '127.0.0.1:0'
		handler:              new_app(provider)
		show_startup_message: false
		accept_timeout:       50 * time.millisecond
	}
	spawn fn (mut s http.Server) {
		s.listen_and_serve()
	}(mut server)
	server.wait_till_running()!
	return 'http://${server.addr}', exporter, provider
}

fn test_a_request_continues_the_callers_trace() {
	url, exporter, _ := start()!
	mut header := http.new_custom_header_from_map({
		'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
	})!
	resp := http.fetch(url: '${url}/hello?name=ada', header: header)!
	assert resp.body == 'hello, ada\n'
	assert resp.header.get_custom('X-Trace-Id')? == '4bf92f3577b34da6a3ce929d0e0e4736'
	spans := exporter.spans()
	// the child ends first
	assert spans.map(it.name) == ['greet', 'GET /hello']
	greet, server := spans[0], spans[1]
	assert server.kind == .server
	assert server.span_context.trace_id.hex() == '4bf92f3577b34da6a3ce929d0e0e4736'
	assert server.parent.span_id.hex() == '00f067aa0ba902b7'
	assert server.parent.remote
	assert greet.parent == server.span_context
	assert server.attributes == [otel.string_attr('http.request.method', 'GET'),
		otel.string_attr('url.path', '/hello'), otel.string_attr('http.route', '/hello'),
		otel.int_attr('http.response.status_code', 200)]
}

fn test_a_request_without_a_trace_starts_one() {
	url, exporter, _ := start()!
	resp := http.get('${url}/hello')!
	assert resp.body == 'hello, world\n'
	spans := exporter.spans()
	assert spans.len == 2
	assert !spans[1].parent.is_valid()
	assert spans[1].span_context.trace_id.hex() == resp.header.get_custom('X-Trace-Id')?
}

fn test_an_unknown_path_is_one_span_with_its_status() {
	url, exporter, _ := start()!
	resp := http.get('${url}/nope')!
	assert resp.status_code == 404
	spans := exporter.spans()
	assert spans.map(it.name) == ['GET unknown']
	assert spans[0].attributes.last().value as i64 == 404
}

fn test_an_unsampled_caller_is_followed() {
	url, exporter, _ := start()!
	mut header := http.new_custom_header_from_map({
		'traceparent': '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00'
	})!
	resp := http.fetch(url: '${url}/hello', header: header)!
	assert resp.status_code == 200
	// the caller didn't sample the trace, so neither does the service
	assert exporter.spans().len == 0
	assert resp.header.get_custom('X-Trace-Id')? == '4bf92f3577b34da6a3ce929d0e0e4736'
}

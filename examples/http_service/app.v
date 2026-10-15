module main

import context
import net.http
import time
import five07.otel
import five07.otel.propagation
import five07.otel.propagation.httpcarrier
import five07.otel.semconv

// App serves `GET /hello?name=…` and traces each request: a server span that
// continues the caller's trace (its `traceparent` header), and a child span for
// the work inside it.
struct App {
	tracer     otel.Tracer
	propagator propagation.TextMapPropagator
}

// new_app returns an app whose spans go to `provider`, read from requests by
// the W3C propagators.
fn new_app(provider otel.TracerProvider) App {
	return App{
		tracer:     provider.tracer('http_service', version: '0.0.0')
		propagator: propagation.default_propagator()
	}
}

// handle is `net.http`'s entry point for each request.
fn (mut app App) handle(req http.Request) http.Response {
	// the caller's trace, if it sent one
	parent := app.propagator.extract(context.background(), httpcarrier.new(req.header))
	path := req.url.all_before('?')
	route := if path == '/hello' { '/hello' } else { 'unknown' }
	ctx, span := app.tracer.start(parent, '${req.method} ${route}',
		kind:       .server
		attributes: [
			otel.string_attr(semconv.http_request_method, req.method.str()),
			otel.string_attr(semconv.url_path, path),
			otel.string_attr(semconv.http_route, route),
		]
	)
	defer {
		span.end()
	}
	mut resp := if route == '/hello' {
		http.new_response(body: app.greet(ctx, query_value(req.url, 'name')))
	} else {
		http.new_response(status: .not_found, body: 'not found')
	}
	span.set_attributes(otel.int_attr(semconv.http_response_status_code, resp.status_code))
	if resp.status_code >= 500 {
		span.set_status(code: .error)
	}
	// the trace id, so a caller can look the request up
	resp.header.add_custom('X-Trace-Id', span.span_context().trace_id.hex()) or {}
	return resp
}

// greet is the request's work, in a span of its own: a child of the request's.
fn (app &App) greet(ctx context.Context, name string) string {
	_, span := app.tracer.start(ctx, 'greet')
	defer {
		span.end()
	}
	who := if name == '' { 'world' } else { name }
	span.set_attributes(otel.int_attr('greet.name_length', who.len))
	time.sleep(time.millisecond)
	return 'hello, ${who}\n'
}

fn query_value(url string, key string) string {
	for pair in url.all_after('?').split('&') {
		if pair.starts_with('${key}=') {
			return pair.all_after('=')
		}
	}
	return ''
}

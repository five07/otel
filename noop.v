module otel

import context

// noop_tracer_provider returns a provider whose spans record nothing. It is
// what a library uses when it isn't given one, and costs next to nothing.
pub fn noop_tracer_provider() TracerProvider {
	return NoopTracerProvider{}
}

// NoopTracerProvider makes `NoopTracer`s.
pub struct NoopTracerProvider {}

// tracer returns a `NoopTracer`.
pub fn (p NoopTracerProvider) tracer(name string, opts TracerOptions) Tracer {
	return NoopTracer{}
}

// NoopTracer starts `NoopSpan`s.
pub struct NoopTracer {}

// start returns a span that records nothing but carries the span context of the
// span in `ctx` (none with `new_root`), and `ctx` with it as the current span.
// So a trace that came in from another service is passed on to the next even
// when nothing in between records it.
pub fn (t NoopTracer) start(ctx context.Context, name string, opts SpanStartOptions) (context.Context, Span) {
	span := NoopSpan{
		context: if opts.new_root { SpanContext{} } else { span_from_context(ctx).span_context() }
	}
	return context_with_span(ctx, span), span
}

// NoopSpan records nothing. It carries a span context, so a trace that came in
// from another service still goes out to the next one when nothing records it.
pub struct NoopSpan {
pub:
	context SpanContext
}

// span_context returns the span context it was made with.
pub fn (s NoopSpan) span_context() SpanContext {
	return s.context
}

// is_recording is always false.
pub fn (s NoopSpan) is_recording() bool {
	return false
}

// set_name does nothing.
pub fn (s NoopSpan) set_name(name string) {}

// set_attributes does nothing.
pub fn (s NoopSpan) set_attributes(attrs ...KeyValue) {}

// add_event does nothing.
pub fn (s NoopSpan) add_event(name string, opts EventOptions) {}

// add_link does nothing.
pub fn (s NoopSpan) add_link(link Link) {}

// set_status does nothing.
pub fn (s NoopSpan) set_status(status Status) {}

// record_error does nothing.
pub fn (s NoopSpan) record_error(err IError, opts ErrorOptions) {}

// end does nothing.
pub fn (s NoopSpan) end(opts EndOptions) {}

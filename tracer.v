module otel

import context

// Tracer starts spans. A library gets one from the `TracerProvider` it was
// given, named after itself, and keeps it.
pub interface Tracer {
	// start starts a span, the child of the span in `ctx` unless `new_root` is
	// set, and returns `ctx` with the new span in it, for the span's children
	start(ctx context.Context, name string, opts SpanStartOptions) (context.Context, Span)
}

// TracerOptions describe the code a `Tracer` instruments, alongside its name.
@[params]
pub struct TracerOptions {
pub:
	// version is the instrumented library's version
	version string
	// schema_url is the semantic conventions' schema the spans follow
	schema_url string
	// attributes describe the instrumentation scope
	attributes []KeyValue
}

// TracerProvider makes tracers. An app builds one and hands it to the
// libraries it uses; a library that is given none uses `noop_tracer_provider()`.
pub interface TracerProvider {
	// tracer returns the tracer for the library named `name`, such as
	// `five07.vgraph`
	tracer(name string, opts TracerOptions) Tracer
}

module api

// Tracer is implemented in another module, as `otel.Tracer` is by the SDK.
pub interface Tracer {
	start(x int) int
}

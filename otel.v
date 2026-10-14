// Package otel is the OpenTelemetry API for V: the types a library uses to
// record spans, and no-op versions of them, so it can be instrumented without
// choosing how telemetry is collected. An app turns recording on by building a
// provider from `five07.otel.sdk.trace` and handing it to the libraries it uses.
module otel

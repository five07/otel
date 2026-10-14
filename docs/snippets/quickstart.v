module main

import context
import five07.otel
import five07.otel.exporters.otlphttp
import five07.otel.sdk.trace

// snippet: quickstart
fn quickstart() ! {
	// once, at startup: spans go in batches to the collector at
	// OTEL_EXPORTER_OTLP_ENDPOINT (default http://localhost:4318)
	exporter := otlphttp.Exporter.new()!
	provider := trace.TracerProvider.new(processors: [trace.BatchSpanProcessor.new(exporter)])!
	defer {
		provider.shutdown() or { eprintln(err) }
	}

	// wherever work happens
	tracer := provider.tracer('shop')
	ctx, span := tracer.start(context.background(), 'checkout', kind: .server)
	_, child := tracer.start(ctx, 'charge', attributes: [otel.int_attr('amount', 120)])
	child.end()
	span.end()
}
// end snippet

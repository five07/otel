module main

import net.http
import os
import five07.otel.exporters.otlphttp
import five07.otel.sdk.trace

fn main() {
	// spans go to the collector the OTEL_EXPORTER_OTLP_* variables name, by
	// default http://localhost:4318, in batches
	exporter := otlphttp.Exporter.new() or {
		eprintln('exporter: ${err}')
		exit(1)
	}
	provider := trace.TracerProvider.new(processors: [trace.BatchSpanProcessor.new(exporter)]) or {
		eprintln('tracing: ${err}')
		exit(1)
	}
	port := os.getenv_opt('PORT') or { '8080' }
	mut server := &http.Server{
		addr:    ':${port}'
		handler: new_app(provider)
	}
	// on ctrl-c, send the spans still queued before exiting
	os.signal_opt(.int, fn [provider] (_ os.Signal) {
		provider.shutdown() or { eprintln('tracing: ${err}') }
		exit(0)
	}) or {}
	server.listen_and_serve()
}

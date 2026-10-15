module main

import time
import five07.otel
import five07.otel.exporters.autoconfig
import five07.otel.exporters.otlphttp
import five07.otel.propagation
import five07.otel.sdk.resource
import five07.otel.sdk.trace

// snippet: configured
// configured_provider sets every setting in code; each one left out comes from
// its environment variable, then the default.
fn configured_provider() !&trace.TracerProvider {
	exporter := otlphttp.Exporter.new(
		endpoint: 'https://collector.example.com:4318/v1/traces'
		headers:  {
			'api-key': 'secret'
		}
		timeout:  5 * time.second
	)!
	processor := trace.BatchSpanProcessor.new(exporter,
		max_queue_size:        4096
		max_export_batch_size: 512
		schedule_delay:        2 * time.second
		export_timeout:        10 * time.second
	)
	return trace.TracerProvider.new(
		resource:   resource.default().merge(resource.Resource.new([
			otel.string_attr('service.name', 'checkout'),
			otel.string_attr('service.version', '1.4.2'),
		], ''))!
		sampler:    trace.parent_based(trace.trace_id_ratio_based(0.25))
		processors: [processor]
		limits:     trace.SpanLimits{
			attribute_count: 64
		}
	)!
}

// propagator honors OTEL_PROPAGATORS; `propagation.default_propagator()` doesn't
// read it.
fn propagator() propagation.TextMapPropagator {
	return propagation.from_env()
}

// end snippet

// snippet: from_env
// env_provider sends spans where OTEL_TRACES_EXPORTER says: `otlp`, `console`,
// both, or nowhere.
fn env_provider() !&trace.TracerProvider {
	return trace.TracerProvider.new(processors: autoconfig.processors_from_env()!)!
}

// end snippet

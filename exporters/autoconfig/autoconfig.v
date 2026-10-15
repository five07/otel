// Package autoconfig builds what the environment asks for that the SDK can't
// build itself, since it would need the exporters: the span processors
// `OTEL_TRACES_EXPORTER` names.
module autoconfig

import os
import five07.otel.exporters.otlphttp
import five07.otel.exporters.stdout
import five07.otel.sdk.trace

// processors_from_env returns a processor for each exporter
// `OTEL_TRACES_EXPORTER` names, comma-separated: `otlp` is a batch processor
// over OTLP/HTTP (set up by the `OTEL_EXPORTER_OTLP_*` variables and the
// `OTEL_BSP_*` ones), and `console` a simple processor over stdout. Unset, or
// `none`, it is none, so an app traces nothing until told where to send it.
// A name this SDK doesn't have is an error, not a warning: skipping it would
// lose every span. The provider is left to the app, which can add processors
// of its own: `trace.TracerProvider.new(processors: autoconfig.processors_from_env()!)`.
pub fn processors_from_env() ![]trace.SpanProcessor {
	mut processors := []trace.SpanProcessor{}
	for name in exporter_names(os.getenv('OTEL_TRACES_EXPORTER'))! {
		match name {
			'otlp' { processors << trace.BatchSpanProcessor.new(otlphttp.Exporter.new()!) }
			'console' { processors << trace.SimpleSpanProcessor.new(stdout.Exporter.new()) }
			else {}
		}
	}
	return processors
}

// exporter_names reads `OTEL_TRACES_EXPORTER`'s value: the names it lists, in
// order, each once, without `none`.
fn exporter_names(value string) ![]string {
	mut names := []string{}
	for raw in value.split(',') {
		name := raw.trim_space().to_lower()
		match name {
			'', 'none' {}
			'otlp', 'console' {
				if name !in names {
					names << name
				}
			}
			else {
				return error('OTEL_TRACES_EXPORTER: `${name}` is not an exporter this SDK has (`otlp`, `console`, `none`)')
			}
		}
	}
	return names
}

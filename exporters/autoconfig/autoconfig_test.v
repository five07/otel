module autoconfig

import os
import five07.otel.sdk.trace

fn test_names_are_read_in_order_once_without_none() {
	assert exporter_names('')! == []
	assert exporter_names('none')! == []
	assert exporter_names('otlp')! == ['otlp']
	assert exporter_names(' Console , otlp,console')! == ['console', 'otlp']
	assert exporter_names('none,console')! == ['console']
}

fn test_an_unknown_exporter_is_an_error() {
	exporter_names('otlp,zipkin') or {
		assert err.msg().contains('`zipkin`')
		return
	}
	assert false
}

fn test_processors_follow_the_environment() {
	os.unsetenv('OTEL_TRACES_EXPORTER')
	assert processors_from_env()!.len == 0
	os.setenv('OTEL_TRACES_EXPORTER', 'console,otlp', true)
	defer {
		os.unsetenv('OTEL_TRACES_EXPORTER')
	}
	processors := processors_from_env()!
	assert processors.len == 2
	assert processors[0] is trace.SimpleSpanProcessor
	assert processors[1] is trace.BatchSpanProcessor
	provider := trace.TracerProvider.new(processors: processors)!
	provider.shutdown()!
	os.setenv('OTEL_TRACES_EXPORTER', 'jaeger', true)
	if _ := processors_from_env() {
		assert false
	}
}

module main

import context
import net.http
import os
import five07.otel
import five07.otel.sdk.trace

fn test_setup_builds_a_provider() {
	os.unsetenv('OTEL_EXPORTER_OTLP_ENDPOINT')
	provider := new_provider()!
	stop(provider)
}

fn memory_provider() (&trace.TracerProvider, &trace.InMemoryExporter) {
	exporter := trace.InMemoryExporter.new()
	provider := trace.TracerProvider.new(
		processors: [trace.SimpleSpanProcessor.new(exporter)]
	) or { panic(err) }
	return provider, exporter
}

fn test_checkout_makes_a_span_and_its_child() {
	provider, exporter := memory_provider()
	checkout(provider, context.background(), 'c-1')!
	spans := exporter.spans()
	assert spans.map(it.name) == ['charge', 'checkout']
	assert spans[0].parent == spans[1].span_context
	assert spans[1].attributes == [otel.string_attr('cart.id', 'c-1'), otel.bool_attr('cart.paid',
		true)]
	// and with no provider, the same code records nothing
	checkout(otel.noop_tracer_provider(), context.background(), 'c-2')!
}

fn test_a_trace_goes_in_and_out() {
	mut req := http.Request{}
	req.header.add_custom('traceparent', '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01')!
	ctx := incoming(req)
	provider, _ := memory_provider()
	ctx2, span := provider.tracer('shop').start(ctx, 'handle')
	headers := outgoing(ctx2)
	assert headers['traceparent'].starts_with('00-4bf92f3577b34da6a3ce929d0e0e4736-')
	assert headers['traceparent'] != '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01'
	span.end()
}

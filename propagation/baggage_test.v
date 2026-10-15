module propagation

import context
import os
import five07.otel

const trace_hex = '4bf92f3577b34da6a3ce929d0e0e4736'
const span_hex = '00f067aa0ba902b7'

fn test_baggage_round_trips() {
	b := otel.Baggage{}.set('tenant', 'acme corp')!.set('tier', 'gold')!
	ctx := otel.context_with_baggage(context.background(), b)
	mut carrier := MapCarrier.new({})
	BaggagePropagator{}.inject(ctx, mut carrier)
	assert carrier.get('baggage')? == 'tenant=acme%20corp,tier=gold'
	back := otel.baggage_from_context(BaggagePropagator{}.extract(context.background(),
		carrier))
	assert back.get('tenant')? == 'acme corp'
	assert back.get('tier')? == 'gold'
}

fn test_no_baggage_injects_nothing_and_bad_baggage_is_dropped() {
	mut carrier := MapCarrier.new({})
	BaggagePropagator{}.inject(context.background(), mut carrier)
	assert carrier.keys().len == 0
	ctx := context.background()
	assert BaggagePropagator{}.extract(ctx, MapCarrier.new({
		'baggage': 'k=a b'
	})) == ctx
}

fn test_the_default_propagator_carries_both() {
	incoming := MapCarrier.new({
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'baggage':     'tenant=acme'
	})
	p := default_propagator()
	ctx := p.extract(context.background(), incoming)
	assert otel.span_from_context(ctx).span_context().trace_id.hex() == trace_hex
	assert otel.baggage_from_context(ctx).get('tenant')? == 'acme'
	mut outgoing := MapCarrier.new({})
	p.inject(ctx, mut outgoing)
	assert outgoing.to_map() == {
		'traceparent': '00-${trace_hex}-${span_hex}-01'
		'baggage':     'tenant=acme'
	}
	assert p.fields() == ['traceparent', 'tracestate', 'baggage']
}

fn test_propagators_from_the_environment() {
	os.unsetenv('OTEL_PROPAGATORS')
	assert from_env().fields() == ['traceparent', 'tracestate', 'baggage']
	os.setenv('OTEL_PROPAGATORS', 'baggage', true)
	assert from_env().fields() == ['baggage']
	os.setenv('OTEL_PROPAGATORS', ' TraceContext , b3 ', true)
	assert from_env().fields() == ['traceparent', 'tracestate']
	os.setenv('OTEL_PROPAGATORS', 'tracecontext,none', true)
	assert from_env().fields() == []
	os.unsetenv('OTEL_PROPAGATORS')
}

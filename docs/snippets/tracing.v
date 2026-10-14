// The guides' code: they copy the regions between `snippet:` comments, and
// `docs_test.v` checks they stay the same. The tests beside this file run it.
module main

import context
import net.http
import five07.otel
import five07.otel.exporters.otlphttp
import five07.otel.propagation
import five07.otel.sdk.trace

// snippet: setup
// new_provider sets up tracing for the app: spans go in batches to the
// collector that OTEL_EXPORTER_OTLP_ENDPOINT names (by default
// http://localhost:4318), described by OTEL_SERVICE_NAME.
fn new_provider() !&trace.TracerProvider {
	exporter := otlphttp.Exporter.new()!
	return trace.TracerProvider.new(
		processors: [trace.BatchSpanProcessor.new(exporter)]
	)!
}

// end snippet

// snippet: spans
// checkout is traced work: a span for it, a child span for a step inside it.
fn checkout(provider otel.TracerProvider, ctx context.Context, cart_id string) ! {
	tracer := provider.tracer('shop', version: '1.0.0')
	ctx2, span := tracer.start(ctx, 'checkout',
		attributes: [
			otel.string_attr('cart.id', cart_id),
		]
	)
	defer {
		span.end()
	}
	charge(tracer, ctx2) or {
		span.record_error(err)
		span.set_status(code: .error)
		return err
	}
	span.set_attributes(otel.bool_attr('cart.paid', true))
}

fn charge(tracer otel.Tracer, ctx context.Context) ! {
	_, span := tracer.start(ctx, 'charge', kind: .client)
	defer {
		span.end()
	}
	// … call the payment service
}

// end snippet

// snippet: propagation
// incoming continues the trace an incoming request carries in its headers.
fn incoming(req http.Request) context.Context {
	carrier := propagation.GetterCarrier{
		get_fn: fn [req] (key string) ?string {
			return req.header.get_custom(key)
		}
	}
	return propagation.default_propagator().extract(context.background(), carrier)
}

// outgoing returns the headers that carry `ctx`'s trace to the next service.
fn outgoing(ctx context.Context) map[string]string {
	mut carrier := propagation.MapCarrier.new({})
	propagation.default_propagator().inject(ctx, mut carrier)
	return carrier.to_map()
}

// end snippet

// snippet: shutdown
// stop sends the spans still queued, and stops tracing; call it before the
// program exits.
fn stop(provider &trace.TracerProvider) {
	provider.shutdown() or { eprintln('tracing: ${err}') }
}
// end snippet

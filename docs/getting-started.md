# Getting started

## Install

otel needs V master (it is built against commit `04cb7fa`, 2026-10-14), and
nothing else: it uses V's standard library alone. Until it is on VPM, install it
from GitHub:

```sh
git clone https://github.com/five07/otel ~/.vmodules/five07/otel
```

It imports as `five07.otel` (the API: spans, attributes, context), with the
SDK in `five07.otel.sdk.trace` and `five07.otel.sdk.resource`, the exporters in
`five07.otel.exporters.otlphttp` and `five07.otel.exporters.stdout`,
`five07.otel.propagation` for headers, and `five07.otel.ref` for refs.

Test and run with `-nocache` (`v -nocache test .`, `v -nocache run .`): V master's
module cache has bugs that otel's code meets (the root README has more).

## Set up a provider

An app builds one tracer provider at its start. Its spans go through a
processor to an exporter: here, in batches, to an OpenTelemetry collector over
OTLP/HTTP.

<!-- snippet: docs/snippets/tracing.v#setup -->
```v
// new_provider sets up tracing for the app: spans go in batches to the
// collector that OTEL_EXPORTER_OTLP_ENDPOINT names (by default
// http://localhost:4318), described by OTEL_SERVICE_NAME.
fn new_provider() !&trace.TracerProvider {
	exporter := otlphttp.Exporter.new()!
	return trace.TracerProvider.new(
		processors: [trace.BatchSpanProcessor.new(exporter)]
	)!
}
```

What isn't given comes from the environment: `OTEL_SERVICE_NAME` names the
service, `OTEL_EXPORTER_OTLP_ENDPOINT` the collector, `OTEL_TRACES_SAMPLER` which
traces are kept. [Configuration](configuration.md) lists them all.

## Record spans

A span is one operation: it starts, gets attributes and events, and ends. The
tracer puts each new span in the context it returns, so spans started from that
context are its children: one trace, drawn as a waterfall.

<!-- snippet: docs/snippets/tracing.v#spans -->
```v
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
```

`checkout` takes an `otel.TracerProvider`, the API's interface, not the SDK's
type: given `otel.noop_tracer_provider()`, the same code runs and records
nothing. A span's methods may be called from any thread; after `end`, they do
nothing.

`record_error` adds an `exception` event with the error's type, but not its
message unless asked (`with_message: true`): messages can quote the values that
failed.

## Across services

A trace continues across services in the W3C `traceparent` header (and
`baggage`). Extract it from an incoming request, and spans started from the
returned context join the caller's trace; inject it into an outgoing request,
and the next service's spans join yours.

<!-- snippet: docs/snippets/tracing.v#propagation -->
```v
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
```

## Shut down

The batch processor holds spans until a batch is full or five seconds pass.
Before the program exits, shut the provider down, or those spans are lost:

<!-- snippet: docs/snippets/tracing.v#shutdown -->
```v
// stop sends the spans still queued, and stops tracing; call it before the
// program exits.
fn stop(provider &trace.TracerProvider) {
	provider.shutdown() or { eprintln('tracing: ${err}') }
}
```

## See them

Run a collector and Jaeger (the root README has the commands, and
[http_service](../examples/http_service) a `docker-compose.yml`), set
`OTEL_SERVICE_NAME`, and open <http://localhost:16686>. To look at spans without
a collector, use the stdout exporter, which writes one JSON line per span:
`stdout.Exporter.new()` in place of `otlphttp.Exporter.new()!`, with a
`trace.SimpleSpanProcessor`.

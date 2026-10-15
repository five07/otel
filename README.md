# otel

[OpenTelemetry](https://opentelemetry.io) for [V](https://vlang.io), on the
standard library alone. Libraries record spans through a small API that costs
nothing until an app turns it on; the app sends them to any OpenTelemetry
collector over OTLP/HTTP. Keyed refs name sensitive values, such as an agent's
tool arguments, in telemetry without revealing them.

**Status:** traces work, toward v0.1.0; metrics and logs come after. Built
against V master at `04cb7fa` (2026-10-14), a daily build that still reports
`V 0.5.2`.

## Quick start

<!-- snippet: docs/snippets/quickstart.v#quickstart -->
```v
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
```

`OTEL_SERVICE_NAME=shop` names the service; [Seeing spans](#seeing-spans-in-a-collector-and-jaeger)
runs a collector and Jaeger to look at them. Install, propagation across
services and the rest: [getting started](docs/getting-started.md).

## What it does

- **The API** (`five07.otel`): spans, attributes, events, links, status,
  `record_error` without the message unless asked; a no-op provider that keeps
  traces together through code that records nothing; context helpers.
- **The SDK** (`five07.otel.sdk.trace`, `.sdk.resource`): a tracer provider;
  samplers (always on and off, ratio by trace id as in Go, parent-based);
  span limits; a simple and a batch processor (queue, drops counted, timed
  export, flush, shutdown with a timeout); the resource from the environment;
  an in-memory exporter for tests, with helpers to find a span by name, check
  its parent and read its attributes.
- **Export**: OTLP/HTTP with JSON (`.exporters.otlphttp`), with the
  specification's endpoint, header and timeout variables and one retry on
  429/502/503/504; JSON lines to stdout (`.exporters.stdout`); the exporters
  `OTEL_TRACES_EXPORTER` names, as processors (`.exporters.autoconfig`).
- **Propagation** (`.propagation`): W3C Trace Context and Baggage, in a map,
  through a function, or in `net.http`'s headers (`.propagation.httpcarrier`).
- **Refs** (`.ref`): HMAC or SHA-256 of a value's RFC 8785 canonical JSON, to
  name a value in a span and find it again with the key.
- **Configuration** by the specification's `OTEL_*` variables; a bad value is a
  warning and its default, unless a default would lose data.

Not yet: metrics and logs; OTLP over gRPC or protobuf, and gzip; resource
detectors beyond the environment; B3 and Jaeger propagators.

## Docs

The [guides](docs/README.md): [getting started](docs/getting-started.md),
[configuration](docs/configuration.md), [refs](docs/refs.md) and
[instrumenting a library](docs/instrumenting-a-library.md). Their code, and the
code above, compiles and runs in [`docs/snippets`](docs/snippets).

The [examples](examples):

- [`http_service`](examples/http_service): an HTTP service that continues its
  callers' traces, with a `docker-compose.yml` for a collector and Jaeger;
- [`refs`](examples/refs): an agent's tool calls named by refs, and found again
  by their arguments.

## Seeing spans in a collector and Jaeger

The OpenTelemetry Collector prints every span it gets (its `debug` exporter)
and passes them on to Jaeger, whose UI draws each trace.
[`examples/http_service`](examples/http_service) has them in a
`docker-compose.yml`; with Docker alone:

```sh
cat > collector.yaml <<'YAML'
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
exporters:
  debug:
    verbosity: detailed
  otlp/jaeger:
    endpoint: otel-dev-jaeger:4317
    tls:
      insecure: true
service:
  pipelines:
    traces:
      receivers: [otlp]
      exporters: [debug, otlp/jaeger]
YAML
docker network create otel-dev
docker run -d --rm --name otel-dev-jaeger --network otel-dev -p 16686:16686 \
  jaegertracing/jaeger:2.4.0
docker run -d --rm --name otel-dev-collector --network otel-dev -p 4318:4318 \
  -v "$PWD/collector.yaml:/etc/otelcol-contrib/config.yaml:ro" \
  otel/opentelemetry-collector-contrib:0.120.0
```

An app using `otlphttp.Exporter.new()` sends to `http://localhost:4318/v1/traces`
by default. `docker logs otel-dev-collector` shows the spans as they arrive, and
<http://localhost:16686> shows the traces by service. To stop:

```sh
docker stop otel-dev-collector otel-dev-jaeger && docker network rm otel-dev
```

## Contributing

Issues and pull requests are welcome on GitHub. The issue forms ask for what's
needed: for a bug, the V and otel versions, how the provider is built, and what
was exported; for a feature, the part of the specification or the Go SDK it
matches, if any.

**Setup.** otel needs V master at the commit in `.github/workflows/ci.yml`
(`V_COMMIT`). Its own modules, the examples and the snippets import it as
`five07.otel`, so link your checkout there:

```sh
v run examples/setup.vsh
```

**Tests.** `v -nocache test .` runs them all, the examples' and the docs' too.
`-nocache`: V master's module cache makes a whole-repository `v test` hang, and
a default `v run` miscompile calls between modules (`regressions/` has the
programs). Run an example with `v -nocache run .`.

**Branches.** Work goes to `develop`, and `main` gets releases, merged from it.

**Docs.** The code in the guides and in this README is copied from
`docs/snippets`, which compiles and runs it; `v test docs/snippets/docs_test.v`
fails when they differ, and `UPDATE_SNIPPETS=1` copies the code over.

## License

MIT, see [LICENSE](LICENSE).

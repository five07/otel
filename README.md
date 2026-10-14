# otel

[OpenTelemetry](https://opentelemetry.io) for [V](https://vlang.io), on the
standard library alone. Libraries record spans through a small API that costs
nothing until an app turns it on; the app sends them to any collector over
OTLP/HTTP. Hashed refs name sensitive values in telemetry without revealing them.

**Status:** not usable yet; work toward v0.1.0 (traces) has started. Built
against V master at `04cb7fa` (2026-10-14), a daily build that still reports
`V 0.5.2`.

## Seeing spans in a collector and Jaeger

The OpenTelemetry Collector prints every span it gets (its `debug` exporter)
and passes them on to Jaeger, whose UI draws each trace. With Docker:

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

Run `v run examples/setup.vsh` once per checkout, so the SDK's modules can import
`five07.otel`. Then test with `v -nocache test .`: V master's module cache can
make a whole-repository `v test` hang. Run an example with `v -nocache run .` for
the same reason.

## License

MIT, see [LICENSE](LICENSE).

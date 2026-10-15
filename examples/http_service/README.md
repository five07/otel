# http_service

A small HTTP service in [V](https://vlang.io), traced with `five07.otel`. Each
request to `GET /hello?name=…` gets a server span, `GET /hello`, with a child
span for its work, `greet`. A request that carries a W3C `traceparent` header
continues the caller's trace; one without starts a new trace. The response's
`X-Trace-Id` header names the trace, to look it up.

Spans go in batches to an OpenTelemetry collector over OTLP/HTTP. On ctrl-c the
service sends the spans still queued before it exits.

Built and tested with V master, like otel (see the root README). It imports otel
as `five07.otel`, so run `v run ../setup.vsh` once per checkout first.

## Running

```sh
docker compose up -d                       # a collector on :4318, Jaeger on :16686
OTEL_SERVICE_NAME=http_service v -nocache run .
curl 'http://localhost:8080/hello?name=ada'
curl -H 'traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01' \
  'http://localhost:8080/hello'            # continues trace 0af76519…
```

Then open <http://localhost:16686>, pick the service `http_service`, and find
the traces; `docker compose logs collector` prints each span as it arrives.
Ctrl-c stops the service, `docker compose down` the rest.

`-nocache`: V master's default `v run` build can miscompile calls between
modules (see `regressions/run_cross_module_interface`); `v -nocache run .` and
a plain `v .` build are fine.

```sh
v -nocache test .                          # the service's tests, over HTTP
```

The tests start the service on a free port with its spans kept in memory, and
check the spans each request makes; they need no collector.

## Settings

| Variable | Default | Meaning |
|----------|---------|---------|
| `PORT` | `8080` | Port to listen on. |
| `OTEL_SERVICE_NAME` | `unknown_service:http_service` | The service's name in the traces. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | The collector. |

Every other `OTEL_*` variable otel reads works too; see
[configuration](../../docs/configuration.md).

## Layout

```
main.v               startup: the exporter, the provider, the server, ctrl-c
app.v                the handler: the span per request, and its child
main_test.v          the tests, over HTTP, with an in-memory exporter
docker-compose.yml   the collector and Jaeger
collector.yaml       the collector's settings: OTLP in, print, on to Jaeger
```

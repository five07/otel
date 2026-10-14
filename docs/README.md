# otel guides

1. [Getting started](getting-started.md): install, a provider, spans, traces
   across services, shutting down.
2. [Configuration](configuration.md): every setting, in code and in the
   environment, and what happens when one is wrong.
3. [Refs](refs.md): naming sensitive values in telemetry without revealing
   them.
4. [Instrumenting a library](instrumenting-a-library.md): adding spans to a
   library that apps can turn on or leave off.

The code in these guides comes from [`snippets/`](snippets), a project that
compiles and runs it in its tests, so it can't drift from otel. The
[examples](../examples) go further: a traced HTTP service with a collector and
Jaeger ([http_service](../examples/http_service)), and refs over an agent's tool
calls ([refs](../examples/refs)).

API reference: `v doc -f html -m -o api .` in the repository (its
`.vdocignore` leaves out the examples), or the doc comments in the source.

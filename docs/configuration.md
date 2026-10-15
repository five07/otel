# Configuration

Every setting can be given in code; what isn't comes from its environment
variable, then from the OpenTelemetry specification's default. The variables
are the specification's, so a deployment configured for another language's SDK
works the same way.

<!-- snippet: docs/snippets/configured.v#configured -->
```v
// configured_provider sets every setting in code; each one left out comes from
// its environment variable, then the default.
fn configured_provider() !&trace.TracerProvider {
	exporter := otlphttp.Exporter.new(
		endpoint: 'https://collector.example.com:4318/v1/traces'
		headers:  {
			'api-key': 'secret'
		}
		timeout:  5 * time.second
	)!
	processor := trace.BatchSpanProcessor.new(exporter,
		max_queue_size:        4096
		max_export_batch_size: 512
		schedule_delay:        2 * time.second
		export_timeout:        10 * time.second
	)
	return trace.TracerProvider.new(
		resource:   resource.default().merge(resource.Resource.new([
			otel.string_attr('service.name', 'checkout'),
			otel.string_attr('service.version', '1.4.2'),
		], ''))!
		sampler:    trace.parent_based(trace.trace_id_ratio_based(0.25))
		processors: [processor]
		limits:     trace.SpanLimits{
			attribute_count: 64
		}
	)!
}

// propagator honors OTEL_PROPAGATORS; `propagation.default_propagator()` doesn't
// read it.
fn propagator() propagation.TextMapPropagator {
	return propagation.from_env()
}
```

## Environment variables

### The service

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_SERVICE_NAME` | `unknown_service:<executable>` | `service.name`; wins over the same key in `OTEL_RESOURCE_ATTRIBUTES`. |
| `OTEL_RESOURCE_ATTRIBUTES` | none | More resource attributes: `key=value,key=value`, values percent-encoded. |

`resource.default()` reads both, over the SDK's own `telemetry.sdk.name`
(`five07.otel`), `.language` (`v`) and `.version`. Attributes merged over it in
code win over the environment's.

### Sampling

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_TRACES_SAMPLER` | `parentbased_always_on` | `always_on`, `always_off`, `traceidratio`, or `parentbased_` before any of them. |
| `OTEL_TRACES_SAMPLER_ARG` | `1` | The ratio of the ratio samplers, from 0 to 1. |

A parent-based sampler follows the caller's decision, so a trace is kept or
dropped whole across services; the ratio decision is the Go SDK's, so V and Go
services with the same ratio keep the same traces.

### Where spans go

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_TRACES_EXPORTER` | none | `otlp`, `console`, or `none`, comma-separated; read by `autoconfig.processors_from_env()`. |

The SDK doesn't read it itself: `TracerProvider.new` takes the processors it is
given. `five07.otel.exporters.autoconfig` turns the variable into processors, a
batch processor over OTLP/HTTP for `otlp` and a simple one over stdout for
`console`, and the app hands them to the provider, with any of its own:

<!-- snippet: docs/snippets/configured.v#from_env -->
```v
// env_provider sends spans where OTEL_TRACES_EXPORTER says: `otlp`, `console`,
// both, or nowhere.
fn env_provider() !&trace.TracerProvider {
	return trace.TracerProvider.new(processors: autoconfig.processors_from_env()!)!
}
```

Unset, it is none, so nothing is sent until the deployment says where; the
specification's default is `otlp`.

### Span limits

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT` | `OTEL_ATTRIBUTE_COUNT_LIMIT`, else 128 | Attributes per span. |
| `OTEL_SPAN_EVENT_COUNT_LIMIT` | 128 | Events per span. |
| `OTEL_SPAN_LINK_COUNT_LIMIT` | 128 | Links per span. |
| `OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT` | 128 | Attributes per event. |
| `OTEL_LINK_ATTRIBUTE_COUNT_LIMIT` | 128 | Attributes per link. |

What goes over a limit is dropped and counted; the counts are exported with the
span.

### The batch processor

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_BSP_SCHEDULE_DELAY` | 5000 ms | The longest a span waits for its batch to fill. |
| `OTEL_BSP_EXPORT_TIMEOUT` | 30000 ms | How long `force_flush` and `shutdown` wait. |
| `OTEL_BSP_MAX_QUEUE_SIZE` | 2048 | Spans waiting for export; more are dropped and counted (`dropped()`). |
| `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` | 512 | Spans per export; at most the queue size. |

### The OTLP exporter

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` | none | The full traces URL, used as it is. |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `http://localhost:4318` | The collector; `/v1/traces` is added after its path. |
| `OTEL_EXPORTER_OTLP_HEADERS`, `…_TRACES_HEADERS` | none | `key=value,…`, values percent-encoded; the traces one wins key by key. |
| `OTEL_EXPORTER_OTLP_TIMEOUT`, `…_TRACES_TIMEOUT` | 10000 ms | One export, its retry included. |
| `OTEL_EXPORTER_OTLP_PROTOCOL`, `…_TRACES_PROTOCOL` | `http/json` | Only `http/json` is sent; another value is a warning. |

A batch the collector is too busy for (429, 502, 503, 504) is sent once more,
after its `Retry-After` or a second, within the timeout.

### Propagation

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_PROPAGATORS` | `tracecontext,baggage` | `tracecontext`, `baggage`, or `none`; read by `propagation.from_env()`. |

`propagation.default_propagator()` is W3C Trace Context and Baggage, whatever the
variable says.

### Refs

| Variable | Default | Meaning |
|----------|---------|---------|
| `OTEL_REF_KEY` | a random key per process, with a warning | The HMAC key of `hmac` refs: hex, at least 32 bytes. Not a specification variable; [refs](refs.md). |

## When a setting is wrong

A malformed variable with a safe default is a warning on stderr, `otel: …`,
and its default is used, as the specification asks: a sampler or ratio, a
limit, a batch setting, a timeout, a header entry, `OTEL_RESOURCE_ATTRIBUTES`
(left out whole; `OTEL_SERVICE_NAME` still applies), a propagator name, a
protocol.

Where a default would do harm, it is an error from the constructor:

- a malformed OTLP endpoint (`otlphttp.Exporter.new`): spans sent elsewhere
  would be lost;
- an exporter name `OTEL_TRACES_EXPORTER` lists that otel doesn't have
  (`autoconfig.processors_from_env`): skipping it would lose every span;
- a malformed or short `OTEL_REF_KEY` (`ref.Refs.new`): a random key in its place
  would make refs no one can look up.

Warnings and errors name the variable and the entry, but never quote a header's
value, which may be a secret.

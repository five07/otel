# Instrumenting a library

A library adds spans to its operations so the apps that use it see them in
their traces, and costs nothing for the apps that don't trace. It imports only
`five07.otel`, the API, never the SDK: the app chooses the SDK, the exporter and
the sampler, and hands the library a provider.

## Take a provider, default to none

otel has no global provider (V would need `-enable-globals` for one), so a
library takes one in its options, with the no-op provider as the default. It asks
for its tracer once, named for itself, with its version.

<!-- snippet: docs/snippets/library.v#library -->
```v
// StoreOptions set up a Store. A library takes the provider it records spans
// with from the app, and records nothing without one.
@[params]
struct StoreOptions {
	tracer_provider otel.TracerProvider = otel.noop_tracer_provider()
}

// Store is a library type: it asks for its tracer once, named for itself.
struct Store {
	tracer otel.Tracer
}

fn Store.new(opts StoreOptions) Store {
	return Store{
		tracer: opts.tracer_provider.tracer('example.blobstore', version: '1.0.0')
	}
}

// get takes the caller's context, so its span is a child of the caller's.
fn (s Store) get(ctx context.Context, key string) !string {
	_, span := s.tracer.start(ctx, 'blobstore.get',
		kind:       .client
		attributes: [otel.string_attr('blobstore.bucket', 'images')]
	)
	defer {
		span.end()
	}
	value := fetch(key) or {
		// the type, not the message: messages can quote the key
		span.record_error(err)
		span.set_status(code: .error)
		return err
	}
	return value
}
```

An app turns the spans on with `Store.new(tracer_provider: provider)`, passing
the `trace.TracerProvider` it built ([getting started](getting-started.md)).
Without it, `start` returns spans that record nothing, and the library's code
runs the same.

## Spans follow the caller's context

Every traced operation takes a `context.Context` and starts its span from it, so
the span is a child of the caller's: the app's request span, or another
library's. Pass the context `start` returns to the operations inside, so their
spans nest under yours. A library that gets no context, or is given
`context.background()`, starts root spans: that works, but they won't join the
app's traces.

Even with the no-op provider, a span started from a context that carries a trace
(such as one extracted from an incoming request) keeps its ids, so a library
with no provider in the middle doesn't break the trace for the code around it.

## Work timed after it ran

When the library learns about work after it happened, such as a database
statement a hook reports with its start time and duration, give the span its
real times:

<!-- snippet: docs/snippets/library.v#after -->
```v
// record_statement reports work timed by the library itself, after it ran: the
// span starts and ends when the work did.
fn (s Store) record_statement(ctx context.Context, started time.Time, took time.Duration, failed bool) {
	_, span := s.tracer.start(ctx, 'SELECT blobs', kind: .client, start: started)
	if failed {
		span.set_status(code: .error)
	}
	span.end(end: started.add(took))
}
```

Times given this way come from the wall clock, which on macOS has microsecond
resolution, while spans started without one share a nanosecond timeline per
trace. So a start taken with `time.now()` just after its parent started can
appear up to a microsecond before it.

## What a span carries

- **Names** are low in variety: `SELECT users`, `query Posts`, `GET /users/:id`;
  not `GET /users/42`. Put the variable parts in attributes.
- **Attributes** use the semantic conventions' names where they fit
  (`five07.otel.semconv`: `http.request.method`, `db.collection.name`, …), and
  the library's own name before its own (`blobstore.bucket`).
- **No values the app didn't put there.** A statement's text with its
  placeholders, not its parameters; an error's type, not its message
  (`record_error` leaves the message out unless asked, since messages can quote
  values); a value that must be identified without being shown as a ref
  ([refs](refs.md)).
- **Status** is `error` when the operation failed; leave it unset when it
  succeeded, and `ok` only to override a failure someone else recorded.
- **`is_recording()`** tells whether the span keeps what it is given: check it
  before building attributes that cost something.

## Testing it

An app's tests, and a library's, read back the spans with the in-memory
exporter:

<!-- snippet: docs/snippets/library_test.v#testing -->
```v
exporter := trace.InMemoryExporter.new()
provider := trace.TracerProvider.new(processors: [trace.SimpleSpanProcessor.new(exporter)])!
store := Store.new(tracer_provider: provider)
// … run the code, then read `exporter.spans()`
```

`docs/snippets/library_test.v` tests the code above that way.

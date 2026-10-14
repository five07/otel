module main

import context
import time
import five07.otel

// snippet: library
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

// end snippet

// snippet: after
// record_statement reports work timed by the library itself, after it ran: the
// span starts and ends when the work did.
fn (s Store) record_statement(ctx context.Context, started time.Time, took time.Duration, failed bool) {
	_, span := s.tracer.start(ctx, 'SELECT blobs', kind: .client, start: started)
	if failed {
		span.set_status(code: .error)
	}
	span.end(end: started.add(took))
}

// end snippet

fn fetch(key string) !string {
	if key == '' {
		return error('no blob')
	}
	return 'blob:${key}'
}

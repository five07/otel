module trace

import context

// SpanProcessor sees every recording span at its start and its end; one that
// exports passes on only the sampled ones. Its methods may be called from any
// thread, and `on_start` and `on_end` should not block: they run in the code
// being traced.
pub interface SpanProcessor {
	// on_start gets the span as it starts, with the context it was started from
	on_start(parent context.Context, span &RecordingSpan)
	// on_end gets the span's data once it has ended
	on_end(span ReadOnlySpan)
	// force_flush exports what the processor holds, and returns when done
	force_flush() !
	// shutdown flushes and stops the processor; later spans are ignored
	shutdown() !
}

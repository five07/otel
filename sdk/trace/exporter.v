module trace

// SpanExporter sends ended spans somewhere: a collector, the console, memory.
// A processor calls `export` from one thread at a time.
pub interface SpanExporter {
	// export sends a batch of spans; an error means the batch was lost
	export(spans []ReadOnlySpan) !
	// shutdown releases what the exporter holds; later exports fail
	shutdown() !
}

// InMemoryExporter keeps the spans it is given, for tests: an app's own tests
// can read back the spans its code made.
@[heap]
pub struct InMemoryExporter {
mut:
	state shared InMemoryState
}

struct InMemoryState {
mut:
	spans   []ReadOnlySpan
	stopped bool
}

// InMemoryExporter.new returns an empty exporter.
pub fn InMemoryExporter.new() &InMemoryExporter {
	return &InMemoryExporter{}
}

// export keeps the spans, after those it has.
pub fn (e &InMemoryExporter) export(spans []ReadOnlySpan) ! {
	lock e.state {
		if e.state.stopped {
			return error('the exporter is shut down')
		}
		e.state.spans << spans
	}
}

// shutdown stops the exporter; the spans it has stay readable.
pub fn (e &InMemoryExporter) shutdown() ! {
	lock e.state {
		e.state.stopped = true
	}
}

// spans returns the spans kept so far, in the order they were exported.
pub fn (e &InMemoryExporter) spans() []ReadOnlySpan {
	return rlock e.state {
		e.state.spans.clone()
	}
}

// reset forgets the spans kept so far.
pub fn (e &InMemoryExporter) reset() {
	lock e.state {
		e.state.spans = []
	}
}

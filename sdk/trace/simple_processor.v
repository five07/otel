module trace

import context

// SimpleProcessorOptions set up a `SimpleSpanProcessor`.
@[params]
pub struct SimpleProcessorOptions {
pub:
	// on_error gets an export's error; by default it is written to stderr
	on_error fn (IError) = report_export_error
}

// SimpleSpanProcessor exports each sampled span as it ends, in the thread that
// ends it. That is simple and loses nothing, but the code being traced waits
// for every export: use it for tests and the console, and a batch processor
// for a collector.
@[heap]
pub struct SimpleSpanProcessor {
	exporter SpanExporter
	on_error fn (IError) @[required]
mut:
	// held during an export too, so exports never overlap
	stopped shared bool
}

// SimpleSpanProcessor.new returns a processor that hands spans to `exporter`.
pub fn SimpleSpanProcessor.new(exporter SpanExporter, opts SimpleProcessorOptions) &SimpleSpanProcessor {
	return &SimpleSpanProcessor{
		exporter: exporter
		on_error: opts.on_error
	}
}

// on_start does nothing.
pub fn (p &SimpleSpanProcessor) on_start(parent context.Context, span &RecordingSpan) {}

// on_end exports the span if it was sampled and the processor is running.
pub fn (p &SimpleSpanProcessor) on_end(span ReadOnlySpan) {
	if !span.span_context.is_sampled() {
		return
	}
	lock p.stopped {
		if !p.stopped {
			p.exporter.export([span]) or { p.on_error(err) }
		}
	}
}

// force_flush has nothing to do: each span is exported as it ends.
pub fn (p &SimpleSpanProcessor) force_flush() ! {}

// shutdown waits for an export under way, stops the processor, and shuts the
// exporter down. Only the first call does anything.
pub fn (p &SimpleSpanProcessor) shutdown() ! {
	first := lock p.stopped {
		was := p.stopped
		p.stopped = true
		!was
	}
	if first {
		p.exporter.shutdown()!
	}
}

fn report_export_error(err IError) {
	eprintln('otel: exporting spans failed: ${err.msg()}')
}

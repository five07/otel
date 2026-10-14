module trace

import context
import os
import strconv
import time

// BatchOptions set up a `BatchSpanProcessor`. What isn't given comes from the
// `OTEL_BSP_*` variables, then the specification's defaults.
@[params]
pub struct BatchOptions {
pub:
	// max_queue_size is how many ended spans may wait for export; more are
	// dropped and counted. `OTEL_BSP_MAX_QUEUE_SIZE`, else 2048
	max_queue_size ?int
	// max_export_batch_size is the most spans sent in one export, at most the
	// queue size. `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`, else 512
	max_export_batch_size ?int
	// schedule_delay is the longest a span waits for a batch to fill before it
	// is exported anyway. `OTEL_BSP_SCHEDULE_DELAY` (ms), else 5 seconds
	schedule_delay ?time.Duration
	// export_timeout bounds how long `force_flush` and `shutdown` wait.
	// `OTEL_BSP_EXPORT_TIMEOUT` (ms), else 30 seconds
	export_timeout ?time.Duration
	// on_error gets an export's error; by default it is written to stderr
	on_error fn (IError) = report_export_error
}

// BatchConfig is a processor's settings once the options and the environment
// are read.
pub struct BatchConfig {
pub:
	max_queue_size        int
	max_export_batch_size int
	schedule_delay        time.Duration
	export_timeout        time.Duration
}

// BatchSpanProcessor queues sampled spans as they end and exports them from a
// thread of its own, in batches: when a batch is full, or when the oldest span
// has waited `schedule_delay`. The code being traced never waits on the
// exporter: when the queue is full, a span is dropped and counted (`dropped`),
// so a slow collector costs spans, not requests. Use it for a collector, and
// call the provider's `shutdown` before the program exits, or the queued spans
// are lost.
@[heap]
pub struct BatchSpanProcessor {
	exporter SpanExporter
	on_error fn (IError) @[required]
	config   BatchConfig
	queue    chan ReadOnlySpan
	control  chan Request
mut:
	state  shared BatchState
	worker thread
}

struct BatchState {
mut:
	dropped u64
	stopped bool
}

// Request asks the worker to export everything queued, then to answer on
// `done`; with `stop`, to end as well.
struct Request {
	stop bool
	done chan bool
}

// BatchSpanProcessor.new starts a processor, and its thread, that exports to
// `exporter`. Malformed `OTEL_BSP_*` variables keep their defaults, with a
// warning on stderr.
pub fn BatchSpanProcessor.new(exporter SpanExporter, opts BatchOptions) &BatchSpanProcessor {
	config, warnings := batch_config(opts)
	warn(warnings)
	mut p := &BatchSpanProcessor{
		exporter: exporter
		on_error: opts.on_error
		config:   config
		queue:    chan ReadOnlySpan{cap: config.max_queue_size}
		control:  chan Request{cap: 1}
	}
	p.worker = spawn p.run()
	return p
}

// config returns the settings the processor uses.
pub fn (p &BatchSpanProcessor) config() BatchConfig {
	return p.config
}

// on_start does nothing.
pub fn (p &BatchSpanProcessor) on_start(parent context.Context, span &RecordingSpan) {}

// on_end queues the span if it was sampled and the processor runs, without
// waiting: if the queue is full, the span is dropped and counted.
pub fn (p &BatchSpanProcessor) on_end(span ReadOnlySpan) {
	if !span.span_context.is_sampled() || p.is_stopped() {
		return
	}
	s := span
	if p.queue.try_push(&s) != .success {
		lock p.state {
			p.state.dropped++
		}
	}
}

// dropped is how many spans were dropped because the queue was full.
pub fn (p &BatchSpanProcessor) dropped() u64 {
	return rlock p.state {
		p.state.dropped
	}
}

// force_flush exports every span queued now, and returns when they are out,
// or with an error after `export_timeout`.
pub fn (p &BatchSpanProcessor) force_flush() ! {
	if p.is_stopped() {
		return
	}
	p.ask(false)!
}

// shutdown stops taking spans, exports those queued, ends the thread, and
// shuts the exporter down; waiting at most `export_timeout` for the thread.
// Only the first call does anything.
pub fn (p &BatchSpanProcessor) shutdown() ! {
	first := lock p.state {
		was := p.state.stopped
		p.state.stopped = true
		!was
	}
	if !first {
		return
	}
	p.ask(true) or {
		p.exporter.shutdown() or {}
		return err
	}
	p.worker.wait()
	p.exporter.shutdown()!
}

fn (p &BatchSpanProcessor) is_stopped() bool {
	return rlock p.state {
		p.state.stopped
	}
}

// ask sends a request to the worker and waits for its answer, both within
// `export_timeout`: a worker stuck in an export may not take the request at
// all, with an earlier one still waiting.
fn (p &BatchSpanProcessor) ask(stop bool) ! {
	timeout := p.config.export_timeout
	deadline := time.now().add(timeout)
	done := chan bool{cap: 1}
	req := Request{
		stop: stop
		done: done
	}
	select {
		p.control <- req {
		}
		timeout {
			return error('the span exporter took longer than ${timeout}; queued spans may be lost')
		}
	}
	mut left := deadline - time.now()
	if left < 0 {
		left = 0
	}
	select {
		_ := <-done {
		}
		left {
			return error('the span exporter took longer than ${timeout}; queued spans may be lost')
		}
	}
}

// run is the processor's thread. It waits for a span, a request, or the end of
// the schedule delay, whichever comes first.
fn (p &BatchSpanProcessor) run() {
	size := p.config.max_export_batch_size
	mut batch := []ReadOnlySpan{cap: size}
	mut next := time.now().add(p.config.schedule_delay)
	for {
		mut wait := next - time.now()
		if wait < 0 {
			wait = 0
		}
		select {
			span := <-p.queue {
				batch << span
				if batch.len >= size {
					p.export(batch)
					batch = []ReadOnlySpan{cap: size}
					next = time.now().add(p.config.schedule_delay)
				}
			}
			req := <-p.control {
				// everything queued goes out, in full batches and the rest
				mut s := ReadOnlySpan{}
				for p.queue.try_pop(mut s) == .success {
					batch << s
					if batch.len >= size {
						p.export(batch)
						batch = []ReadOnlySpan{cap: size}
					}
				}
				if batch.len > 0 {
					p.export(batch)
					batch = []ReadOnlySpan{cap: size}
				}
				next = time.now().add(p.config.schedule_delay)
				req.done <- true
				if req.stop {
					return
				}
			}
			wait {
				if batch.len > 0 {
					p.export(batch)
					batch = []ReadOnlySpan{cap: size}
				}
				next = time.now().add(p.config.schedule_delay)
			}
		}
	}
}

fn (p &BatchSpanProcessor) export(batch []ReadOnlySpan) {
	p.exporter.export(batch) or { p.on_error(err) }
}

// batch_config reads the options, then the `OTEL_BSP_*` variables, then the
// defaults. A malformed variable keeps its default, with a warning; a batch
// size above the queue size is cut to it.
fn batch_config(opts BatchOptions) (BatchConfig, []string) {
	mut warnings := []string{}
	queue := opts.max_queue_size or {
		bsp_env_int('OTEL_BSP_MAX_QUEUE_SIZE', 2048, mut warnings)
	}
	mut batch := opts.max_export_batch_size or {
		bsp_env_int('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', 512, mut warnings)
	}
	q := if queue > 0 { queue } else { 2048 }
	if batch <= 0 {
		batch = 512
	}
	if batch > q {
		warnings << 'the export batch size ${batch} is above the queue size ${q}; using ${q}'
		batch = q
	}
	return BatchConfig{
		max_queue_size:        q
		max_export_batch_size: batch
		schedule_delay:        opts.schedule_delay or {
			bsp_env_int('OTEL_BSP_SCHEDULE_DELAY', 5000, mut warnings) * time.millisecond
		}
		export_timeout:        opts.export_timeout or {
			bsp_env_int('OTEL_BSP_EXPORT_TIMEOUT', 30_000, mut warnings) * time.millisecond
		}
	}, warnings
}

fn bsp_env_int(name string, default_value int, mut warnings []string) int {
	value := os.getenv(name).trim_space()
	if value == '' {
		return default_value
	}
	n := strconv.atoi(value) or {
		warnings << '${name}: `${value}` is not a whole number; using ${default_value}'
		return default_value
	}
	if n <= 0 {
		warnings << '${name}: `${value}` is not above 0; using ${default_value}'
		return default_value
	}
	return n
}

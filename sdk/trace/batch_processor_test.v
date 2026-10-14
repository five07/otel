module trace

import context
import os
import time
import five07.otel

// Batches records the batches it is given. With `hold` set, each export
// announces itself on `entered` and then waits for `release`.
@[heap]
struct Batches {
	hold    bool
	entered chan bool = chan bool{cap: 100}
	release chan bool = chan bool{cap: 100}
mut:
	log shared BatchLog
}

struct BatchLog {
mut:
	sizes     []int
	names     []string
	shutdowns int
}

fn (b &Batches) export(spans []ReadOnlySpan) ! {
	if b.hold {
		b.entered <- true
		_ := <-b.release
	}
	lock b.log {
		b.log.sizes << spans.len
		for s in spans {
			b.log.names << s.name
		}
	}
}

fn (b &Batches) shutdown() ! {
	lock b.log {
		b.log.shutdowns++
	}
}

fn (b &Batches) sizes() []int {
	return rlock b.log {
		b.log.sizes.clone()
	}
}

fn (b &Batches) names() []string {
	return rlock b.log {
		b.log.names.clone()
	}
}

// wait_for polls `cond` for up to two seconds: the processor's thread works
// on its own time.
fn wait_for(cond fn () bool) bool {
	for _ in 0 .. 2000 {
		if cond() {
			return true
		}
		time.sleep(time.millisecond)
	}
	return cond()
}

fn sampled_span(name string) ReadOnlySpan {
	return ReadOnlySpan{
		name:         name
		span_context: otel.SpanContext{
			flags: otel.TraceFlags{}.with_sampled(true)
		}
	}
}

fn test_full_batches_go_out_at_once_and_the_rest_at_shutdown() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b, max_export_batch_size: 3)
	for i in 0 .. 7 {
		p.on_end(sampled_span('s${i}'))
	}
	assert wait_for(fn [b] () bool {
		return b.sizes().len == 2
	})
	assert b.sizes() == [3, 3]
	p.shutdown()!
	assert b.sizes() == [3, 3, 1]
	assert b.names() == ['s0', 's1', 's2', 's3', 's4', 's5', 's6']
	assert rlock b.log {
		b.log.shutdowns
	} == 1
	assert p.dropped() == 0
}

fn test_unsampled_spans_are_not_queued() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b)
	p.on_end(ReadOnlySpan{
		name: 'record only'
	})
	p.shutdown()!
	assert b.sizes().len == 0
}

fn test_a_full_queue_drops_and_counts_without_waiting() {
	b := &Batches{
		hold: true
	}
	p := BatchSpanProcessor.new(b, max_queue_size: 4, max_export_batch_size: 1)
	// the thread takes the first span and is held in its export
	p.on_end(sampled_span('first'))
	select {
		_ := <-b.entered {
		}
		2 * time.second {
			assert false, 'the first span was never exported'
		}
	}
	// four more fill the queue; the next five are dropped, and none waits:
	// they are ended from a thread of their own, so a wait fails the test
	// instead of hanging it
	done := chan bool{cap: 1}
	spawn fn (p &BatchSpanProcessor, done chan bool) {
		for i in 0 .. 9 {
			p.on_end(sampled_span('s${i}'))
		}
		done <- true
	}(p, done)
	select {
		_ := <-done {
		}
		500 * time.millisecond {
			assert false, 'on_end waited for the exporter'
		}
	}
	assert p.dropped() == 5
	// let every export through: the first span and the four queued go out
	for _ in 0 .. 10 {
		b.release <- true
	}
	p.shutdown()!
	assert b.names() == ['first', 's0', 's1', 's2', 's3']
	assert p.dropped() == 5
}

fn test_after_shutdown_spans_are_ignored_not_dropped() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b)
	p.shutdown()!
	p.shutdown()!
	p.on_end(sampled_span('late'))
	assert p.dropped() == 0
	assert b.sizes().len == 0
	assert rlock b.log {
		b.log.shutdowns
	} == 1
}

// Failing fails each export, to show its errors reach `on_error`.
struct FailingBatches {}

fn (f FailingBatches) export(spans []ReadOnlySpan) ! {
	return error('collector unreachable')
}

fn (f FailingBatches) shutdown() ! {}

@[heap]
struct ErrorLog {
mut:
	msgs shared []string
}

fn test_export_errors_reach_on_error() {
	log := &ErrorLog{}
	p := BatchSpanProcessor.new(FailingBatches{},
		max_export_batch_size: 1
		on_error:              fn [log] (err IError) {
			lock log.msgs {
				log.msgs << err.msg()
			}
		}
	)
	p.on_end(sampled_span('a'))
	p.on_end(sampled_span('b'))
	p.shutdown()!
	assert rlock log.msgs {
		log.msgs.clone()
	} == ['collector unreachable', 'collector unreachable']
}

fn test_many_threads_through_a_provider() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b, max_queue_size: 10_000, max_export_batch_size: 100)
	provider := TracerProvider.new(
		sampler:    always_on_sampler()
		processors: [p]
		limits:     SpanLimits{}
	)!
	tracer := provider.tracer('lib')
	mut threads := []thread{}
	for _ in 0 .. 8 {
		threads << spawn fn (tracer otel.Tracer) {
			for _ in 0 .. 500 {
				_, span := tracer.start(context.background(), 'work')
				span.end()
			}
		}(tracer)
	}
	threads.wait()
	provider.shutdown()!
	assert b.names().len == 4000
	for size in b.sizes() {
		assert size <= 100
	}
	assert p.dropped() == 0
}

fn test_a_batch_that_does_not_fill_goes_out_after_the_delay() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b, schedule_delay: 50 * time.millisecond)
	started := time.now()
	p.on_end(sampled_span('a'))
	p.on_end(sampled_span('b'))
	assert wait_for(fn [b] () bool {
		return b.sizes().len == 1
	})
	assert b.sizes() == [2]
	assert time.since(started) >= 40 * time.millisecond
	p.shutdown()!
	assert b.sizes() == [2]
}

fn test_force_flush_exports_what_is_queued_and_keeps_running() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b, schedule_delay: time.hour, max_export_batch_size: 2)
	for i in 0 .. 3 {
		p.on_end(sampled_span('s${i}'))
	}
	p.force_flush()!
	assert b.names() == ['s0', 's1', 's2']
	p.on_end(sampled_span('s3'))
	p.force_flush()!
	assert b.names() == ['s0', 's1', 's2', 's3']
	assert b.sizes().len == 3
	p.shutdown()!
	// after shutdown, a flush has nothing to do
	p.force_flush()!
}

fn test_force_flush_and_shutdown_give_up_after_the_export_timeout() {
	b := &Batches{
		hold: true
	}
	p := BatchSpanProcessor.new(b,
		max_export_batch_size: 1
		export_timeout:        100 * time.millisecond
	)
	p.on_end(sampled_span('stuck'))
	select {
		_ := <-b.entered {
		}
		2 * time.second {
			assert false, 'the span was never exported'
		}
	}
	// both run on a thread of their own, so a wait past the timeout fails the
	// test instead of hanging it
	results := chan string{cap: 2}
	spawn fn (p &BatchSpanProcessor, results chan string) {
		p.force_flush() or { results <- err.msg() }
		p.shutdown() or { results <- err.msg() }
		results <- 'returned'
	}(p, results)
	for want in ['took longer than', 'took longer than', 'returned'] {
		select {
			got := <-results {
				assert got.contains(want), got
			}
			2 * time.second {
				assert false, 'force_flush or shutdown waited past the export timeout'
			}
		}
	}
	// the exporter is still shut down
	assert rlock b.log {
		b.log.shutdowns
	} == 1
	for _ in 0 .. 10 {
		b.release <- true
	}
}

fn test_the_provider_flushes_a_batch_processor() {
	b := &Batches{}
	p := BatchSpanProcessor.new(b, schedule_delay: time.hour)
	provider := TracerProvider.new(
		sampler:    always_on_sampler()
		processors: [p]
		limits:     SpanLimits{}
	)!
	_, span := provider.tracer('lib').start(context.background(), 'a')
	span.end()
	provider.force_flush()!
	assert b.names() == ['a']
	provider.shutdown()!
}

fn test_settings_from_options_and_the_environment() {
	names := ['OTEL_BSP_SCHEDULE_DELAY', 'OTEL_BSP_EXPORT_TIMEOUT', 'OTEL_BSP_MAX_QUEUE_SIZE',
		'OTEL_BSP_MAX_EXPORT_BATCH_SIZE']
	for name in names {
		os.unsetenv(name)
	}
	d, w := batch_config(BatchOptions{})
	assert d == BatchConfig{
		max_queue_size:        2048
		max_export_batch_size: 512
		schedule_delay:        5 * time.second
		export_timeout:        30 * time.second
	}
	assert w.len == 0
	os.setenv('OTEL_BSP_SCHEDULE_DELAY', '250', true)
	os.setenv('OTEL_BSP_EXPORT_TIMEOUT', '1000', true)
	os.setenv('OTEL_BSP_MAX_QUEUE_SIZE', '100', true)
	os.setenv('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', '10', true)
	e, _ := batch_config(BatchOptions{})
	assert e == BatchConfig{
		max_queue_size:        100
		max_export_batch_size: 10
		schedule_delay:        250 * time.millisecond
		export_timeout:        time.second
	}
	// code wins
	c, _ := batch_config(max_queue_size: 7, schedule_delay: time.minute)
	assert c.max_queue_size == 7
	assert c.max_export_batch_size == 7
	assert c.schedule_delay == time.minute
	// a bad variable keeps its default, with a warning; a batch above the queue
	// is cut to it
	os.setenv('OTEL_BSP_EXPORT_TIMEOUT', '0', true)
	os.setenv('OTEL_BSP_SCHEDULE_DELAY', 'soon', true)
	os.setenv('OTEL_BSP_MAX_QUEUE_SIZE', '-5', true)
	os.setenv('OTEL_BSP_MAX_EXPORT_BATCH_SIZE', '4096', true)
	f, warnings := batch_config(BatchOptions{})
	assert f.schedule_delay == 5 * time.second
	assert f.max_queue_size == 2048
	assert f.max_export_batch_size == 2048
	assert warnings == ['OTEL_BSP_MAX_QUEUE_SIZE: `-5` is not above 0; using 2048',
		'the export batch size 4096 is above the queue size 2048; using 2048',
		'OTEL_BSP_SCHEDULE_DELAY: `soon` is not a whole number; using 5000',
		'OTEL_BSP_EXPORT_TIMEOUT: `0` is not above 0; using 30000']
	assert f.export_timeout == 30 * time.second
	for name in names {
		os.unsetenv(name)
	}
}

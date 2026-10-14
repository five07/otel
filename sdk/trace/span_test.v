module trace

import time
import five07.otel

// Ended collects what spans hand to `on_end`.
@[heap]
struct Ended {
mut:
	spans shared []ReadOnlySpan
}

fn (e &Ended) all() []ReadOnlySpan {
	return rlock e.spans {
		e.spans.clone()
	}
}

fn span_context(span_hex string) otel.SpanContext {
	return otel.SpanContext{
		trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736') or { panic(err) }
		span_id:  otel.SpanId.from_hex(span_hex) or { panic(err) }
	}
}

fn new_span(e &Ended, c SpanConfig) &RecordingSpan {
	return new_recording_span(SpanConfig{
		...c
		context: span_context('00f067aa0ba902b7')
		on_end:  fn [e] (s ReadOnlySpan) {
			lock e.spans {
				e.spans << s
			}
		}
	})
}

fn test_a_span_keeps_what_it_is_given_and_hands_it_on_at_its_end() {
	e := &Ended{}
	parent := span_context('b7ad6b7169203331')
	s := new_span(e, SpanConfig{
		name:       'GET'
		parent:     parent
		kind:       .server
		attributes: [otel.string_attr('http.request.method', 'GET')]
		scope:      InstrumentationScope{
			name:    'five07.vgraph'
			version: '0.1.0'
		}
		on_end:     fn (_ ReadOnlySpan) {}
	})
	assert s.is_recording()
	s.set_name('GET /users')
	s.set_attributes(otel.int_attr('http.response.status_code', 200))
	s.add_event('cache.miss')
	s.set_status(code: .ok)
	assert e.all().len == 0
	s.end()
	assert !s.is_recording()
	ended := e.all()
	assert ended.len == 1
	r := ended[0]
	assert r.name == 'GET /users'
	assert r.span_context == s.span_context()
	assert r.parent == parent
	assert r.kind == .server
	assert r.attributes == [otel.string_attr('http.request.method', 'GET'),
		otel.int_attr('http.response.status_code', 200)]
	assert r.events.len == 1
	assert r.events[0].name == 'cache.miss'
	assert r.status.code == .ok
	assert r.scope.name == 'five07.vgraph'
	assert r.start_ns > 0
	assert r.end_ns >= r.start_ns
}

fn test_end_happens_once_and_later_calls_do_nothing() {
	e := &Ended{}
	s := new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {})
	s.end()
	s.end()
	s.set_name('b')
	s.set_attributes(otel.string_attr('k', 'v'))
	s.add_event('late')
	s.add_link(otel.Link{
		span_context: span_context('b7ad6b7169203331')
	})
	s.set_status(code: .error)
	s.record_error(error('late'))
	assert e.all().len == 1
	r := s.read_only()
	assert r.name == 'a'
	assert r.attributes.len == 0
	assert r.events.len == 0
	assert r.links.len == 0
	assert r.status.code == .unset
}

fn test_attributes_replace_by_key_and_stop_at_the_limit() {
	e := &Ended{}
	s := new_span(e,
		name:       'a'
		limits:     SpanLimits{
			attribute_count: 2
		}
		attributes: [otel.string_attr('a', '1')]
		on_end:     fn (_ ReadOnlySpan) {}
	)
	s.set_attributes(otel.string_attr('b', '2'), otel.string_attr('c', '3'),
		otel.string_attr('a', '4'), otel.string_attr('', 'x'), otel.string_attr('d', '5'))
	r := s.read_only()
	assert r.attributes == [otel.string_attr('a', '4'), otel.string_attr('b', '2')]
	// c and d were new keys past the limit; the empty key isn't counted
	assert r.dropped_attributes == 2
}

fn test_events_stop_at_their_limits() {
	e := &Ended{}
	s := new_span(e,
		name:   'a'
		limits: SpanLimits{
			event_count:          2
			attributes_per_event: 1
		}
		on_end: fn (_ ReadOnlySpan) {}
	)
	at := time.unix(1_700_000_000)
	s.add_event('one',
		attributes: [otel.string_attr('a', '1'), otel.string_attr('b', '2'),
			otel.string_attr('a', '3')]
		timestamp:  at
	)
	s.add_event('two')
	s.add_event('three')
	r := s.read_only()
	assert r.events.map(it.name) == ['one', 'two']
	assert r.dropped_events == 1
	assert r.events[0].attributes == [otel.string_attr('a', '3')]
	assert r.events[0].dropped_attributes == 1
	assert r.events[0].time_ns == at.unix_nano()
	assert r.events[1].time_ns > 0
}

fn test_links_skip_invalid_contexts_and_stop_at_their_limit() {
	e := &Ended{}
	s := new_span(e,
		name:   'batch'
		limits: SpanLimits{
			link_count: 1
		}
		links:  [
			otel.Link{},
			otel.Link{
				span_context: span_context('b7ad6b7169203331')
				attributes:   [otel.int_attr('n', 1)]
			},
		]
		on_end: fn (_ ReadOnlySpan) {}
	)
	s.add_link(otel.Link{
		span_context: span_context('00000000000000a1')
	})
	r := s.read_only()
	assert r.links.len == 1
	assert r.links[0].span_context == span_context('b7ad6b7169203331')
	assert r.links[0].attributes == [otel.int_attr('n', 1)]
	assert r.dropped_links == 1
}

fn test_status_rules() {
	e := &Ended{}
	s := new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {})
	s.set_status(code: .unset, description: 'ignored')
	assert s.read_only().status == otel.Status{}
	s.set_status(code: .error, description: 'timed out')
	assert s.read_only().status == otel.Status{
		code:        .error
		description: 'timed out'
	}
	// unset doesn't clear an error
	s.set_status(code: .unset)
	assert s.read_only().status.code == .error
	// ok overrides an error, and drops a description
	s.set_status(code: .ok, description: 'dropped')
	assert s.read_only().status == otel.Status{
		code: .ok
	}
	// and nothing overrides ok
	s.set_status(code: .error, description: 'too late')
	assert s.read_only().status.code == .ok
}

struct QueryError {
	Error
}

fn (e QueryError) msg() string {
	return 'no row with email alice@example.com'
}

fn test_record_error_leaves_out_the_message_unless_asked() {
	e := &Ended{}
	s := new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {})
	s.record_error(QueryError{})
	s.record_error(QueryError{}, with_message: true, attributes: [otel.bool_attr('retry', true)])
	r := s.read_only()
	assert r.events.len == 2
	assert r.events[0].name == 'exception'
	assert r.events[0].attributes == [otel.string_attr('exception.type', 'QueryError')]
	assert r.events[1].attributes == [
		otel.string_attr('exception.type', 'QueryError'),
		otel.string_attr('exception.message', 'no row with email alice@example.com'),
		otel.bool_attr('retry', true),
	]
	// the status is the caller's to set
	assert r.status.code == .unset
}

fn test_explicit_start_and_end_times() {
	e := &Ended{}
	start := time.unix(1_700_000_000)
	end := time.unix(1_700_000_002)
	s := new_span(e, name: 'statement', start: start, on_end: fn (_ ReadOnlySpan) {})
	s.end(end: end)
	r := e.all()[0]
	assert r.start_ns == 1_700_000_000_000_000_000
	assert r.end_ns == 1_700_000_002_000_000_000
}

fn test_the_duration_comes_from_the_monotonic_clock() {
	e := &Ended{}
	s := new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {})
	time.sleep(5 * time.millisecond)
	s.end()
	r := e.all()[0]
	assert r.end_ns - r.start_ns >= 5_000_000
	assert r.end_ns - r.start_ns < 5_000_000_000
}

fn test_read_only_is_a_copy() {
	e := &Ended{}
	s := new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {})
	s.set_attributes(otel.string_attr('a', '1'))
	before := s.read_only()
	s.set_attributes(otel.string_attr('a', '2'), otel.string_attr('b', '3'))
	assert before.attributes == [otel.string_attr('a', '1')]
}

fn test_a_span_is_safe_across_threads() {
	e := &Ended{}
	s := new_span(e,
		name:   'a'
		limits: SpanLimits{
			attribute_count: 1000
			event_count:     10_000
		}
		on_end: fn (_ ReadOnlySpan) {}
	)
	mut threads := []thread{}
	for t in 0 .. 8 {
		threads << spawn fn (s otel.Span, t int) {
			for i in 0 .. 500 {
				s.set_attributes(otel.int_attr('t${t}', i))
				s.add_event('e')
			}
		}(s, t)
	}
	threads.wait()
	s.end()
	r := e.all()[0]
	assert r.attributes.len == 8
	for kv in r.attributes {
		assert kv.value as i64 == 499
	}
	assert r.events.len == 4000
}

fn test_a_recording_span_is_an_otel_span() {
	e := &Ended{}
	span := otel.Span(new_span(e, name: 'a', on_end: fn (_ ReadOnlySpan) {}))
	span.end()
	assert e.all().len == 1
}

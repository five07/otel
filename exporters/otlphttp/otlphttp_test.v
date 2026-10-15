module otlphttp

import json2
import os
import time
import five07.otel
import five07.otel.sdk.trace

const env_names = ['OTEL_EXPORTER_OTLP_ENDPOINT', 'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT',
	'OTEL_EXPORTER_OTLP_HEADERS', 'OTEL_EXPORTER_OTLP_TRACES_HEADERS', 'OTEL_EXPORTER_OTLP_TIMEOUT',
	'OTEL_EXPORTER_OTLP_TRACES_TIMEOUT', 'OTEL_EXPORTER_OTLP_PROTOCOL',
	'OTEL_EXPORTER_OTLP_TRACES_PROTOCOL']

fn clear_env() {
	for name in env_names {
		os.unsetenv(name)
	}
}

fn test_defaults() {
	clear_env()
	c, w := resolve(Options{})!
	assert c.url == 'http://localhost:4318/v1/traces'
	assert c.headers.len == 0
	assert c.timeout == 10 * time.second
	assert w.len == 0
}

fn test_endpoints_and_their_paths() {
	clear_env()
	for base, want in {
		'http://collector:4318':     'http://collector:4318/v1/traces'
		'http://collector:4318/':    'http://collector:4318/v1/traces'
		'https://example.com/otlp':  'https://example.com/otlp/v1/traces'
		'https://example.com/otlp/': 'https://example.com/otlp/v1/traces'
	} {
		os.setenv('OTEL_EXPORTER_OTLP_ENDPOINT', base, true)
		c, _ := resolve(Options{})!
		assert c.url == want
	}
	// the traces variable is used as it is, over the general one
	os.setenv('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT', 'http://traces:9999/custom', true)
	c, _ := resolve(Options{})!
	assert c.url == 'http://traces:9999/custom'
	// and code wins over both
	d, _ := resolve(endpoint: 'https://code:4318/v1/traces')!
	assert d.url == 'https://code:4318/v1/traces'
	clear_env()
}

fn test_a_malformed_endpoint_is_an_error() {
	clear_env()
	for bad in ['collector:4318', 'ftp://collector', 'http://', 'not a url'] {
		os.setenv('OTEL_EXPORTER_OTLP_ENDPOINT', bad, true)
		if _ := Exporter.new() {
			assert false, '`${bad}` was taken'
		}
	}
	clear_env()
	if _ := Exporter.new(endpoint: 'localhost:4318') {
		assert false, 'a URL with no scheme was taken'
	}
}

fn test_headers_merge_and_decode() {
	clear_env()
	os.setenv('OTEL_EXPORTER_OTLP_HEADERS', 'api-key=general, x-team = blog ,bad, =v,enc=a%20b', true)
	os.setenv('OTEL_EXPORTER_OTLP_TRACES_HEADERS', 'api-key=traces,pct=%zzsecret', true)
	c, w := resolve(
		headers: {
			'x-team': 'code'
		}
	)!
	assert c.headers == {
		'api-key': 'traces'
		'x-team':  'code'
		'enc':     'a b'
	}
	assert w == ['OTEL_EXPORTER_OTLP_HEADERS: entry 3 is not `key=value`; skipped',
		'OTEL_EXPORTER_OTLP_HEADERS: entry 4 is not `key=value`; skipped',
		'OTEL_EXPORTER_OTLP_TRACES_HEADERS: the value of `pct` has a bad percent-encoding; skipped']
	// a warning never quotes a value
	for warning in w {
		assert !warning.contains('secret')
	}
	clear_env()
}

fn test_timeouts_and_protocol() {
	clear_env()
	os.setenv('OTEL_EXPORTER_OTLP_TIMEOUT', '2500', true)
	a, _ := resolve(Options{})!
	assert a.timeout == 2500 * time.millisecond
	os.setenv('OTEL_EXPORTER_OTLP_TRACES_TIMEOUT', '700', true)
	b, _ := resolve(Options{})!
	assert b.timeout == 700 * time.millisecond
	c, _ := resolve(timeout: time.second)!
	assert c.timeout == time.second
	os.setenv('OTEL_EXPORTER_OTLP_TRACES_TIMEOUT', 'soon', true)
	os.setenv('OTEL_EXPORTER_OTLP_PROTOCOL', 'grpc', true)
	d, w := resolve(Options{})!
	assert d.timeout == 2500 * time.millisecond
	assert w == [
		'OTEL_EXPORTER_OTLP_TRACES_TIMEOUT: `soon` is not a number of milliseconds above 0; using 2500',
		'OTEL_EXPORTER_OTLP_PROTOCOL: `grpc` is not supported; this exporter sends http/json',
	]
	clear_env()
}

// Fake answers each post with the next scripted reply, and records the posts
// and the waits.
@[heap]
struct Fake {
	replies []Reply
mut:
	log shared FakeLog
}

struct FakeLog {
mut:
	urls    []string
	headers []map[string]string
	bodies  []string
	waits   []time.Duration
}

fn (f &Fake) post(url string, headers map[string]string, body string, timeout time.Duration) !Reply {
	n := lock f.log {
		f.log.urls << url
		f.log.headers << headers.clone()
		f.log.bodies << body
		f.log.urls.len
	}
	if n > f.replies.len {
		return error('connection refused')
	}
	return f.replies[n - 1]
}

fn (f &Fake) posts() int {
	return rlock f.log {
		f.log.urls.len
	}
}

fn (f &Fake) waits() []time.Duration {
	return rlock f.log {
		f.log.waits.clone()
	}
}

fn exporter_with(f &Fake, timeout time.Duration) &Exporter {
	return &Exporter{
		config:    Config{
			url:     'http://collector:4318/v1/traces'
			headers: {
				'api-key': 'k'
			}
			timeout: timeout
		}
		transport: f
		sleep:     fn [f] (d time.Duration) {
			lock f.log {
				f.log.waits << d
			}
		}
	}
}

fn one_span() []trace.ReadOnlySpan {
	return [
		trace.ReadOnlySpan{
			name:         'GET /users'
			span_context: otel.SpanContext{
				trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736') or {
					panic(err)
				}
				span_id:  otel.SpanId.from_hex('00f067aa0ba902b7') or { panic(err) }
			}
		},
	]
}

fn test_a_success_is_one_post_of_otlp_json() {
	f := &Fake{
		replies: [Reply{
			status: 200
		}]
	}
	exporter_with(f, time.second).export(one_span())!
	assert f.posts() == 1
	log := rlock f.log {
		f.log
	}
	assert log.urls[0] == 'http://collector:4318/v1/traces'
	assert log.headers[0]['api-key'] == 'k'
	body := json2.decode[json2.Any](log.bodies[0])!.as_map()
	assert 'resourceSpans' in body
	assert log.bodies[0].contains('"name":"GET /users"')
}

fn test_a_busy_collector_is_tried_once_more_after_retry_after() {
	f := &Fake{
		replies: [Reply{
			status:      503
			retry_after: '2'
		}, Reply{
			status: 202
		}]
	}
	exporter_with(f, 10 * time.second).export(one_span())!
	assert f.posts() == 2
	assert f.waits() == [2 * time.second]
}

fn test_retry_after_forms() {
	now := time.unix(1_700_000_000)
	assert retry_delay('', now) == time.second
	assert retry_delay('3', now) == 3 * time.second
	assert retry_delay('0', now) == 0
	assert retry_delay('soon', now) == time.second
	assert retry_delay('Tue, 14 Nov 2023 22:13:25 GMT', now) == 5 * time.second
	assert retry_delay('Tue, 14 Nov 2023 22:13:15 GMT', now) == 0
	for status in [429, 502, 503, 504] {
		assert is_retryable(status)
	}
	for status in [400, 401, 404, 413, 500] {
		assert !is_retryable(status)
	}
}

fn test_a_second_failure_loses_the_batch() {
	f := &Fake{
		replies: [Reply{
			status: 429
		}, Reply{
			status: 503
			body:   'overloaded'
		}]
	}
	exporter_with(f, 10 * time.second).export(one_span()) or {
		assert err.msg() == 'the collector answered 429, then 503: overloaded'
		assert f.posts() == 2
		assert f.waits() == [time.second]
		return
	}
	assert false, 'a lost batch was not reported'
}

fn test_other_statuses_are_not_retried() {
	f := &Fake{
		replies: [Reply{
			status: 400
			body:   '{"message":"bad span"}'
		}]
	}
	exporter_with(f, time.second).export(one_span()) or {
		assert err.msg() == 'the collector answered 400: {"message":"bad span"}'
		assert f.posts() == 1
		return
	}
	assert false
}

fn test_a_wait_past_the_timeout_is_not_made() {
	f := &Fake{
		replies: [Reply{
			status:      503
			retry_after: '60'
		}, Reply{
			status: 200
		}]
	}
	exporter_with(f, 5 * time.second).export(one_span()) or {
		assert err.msg().contains('longer than the timeout')
		assert f.posts() == 1
		assert f.waits().len == 0
		return
	}
	assert false
}

fn test_a_network_error_is_returned() {
	f := &Fake{}
	exporter_with(f, time.second).export(one_span()) or {
		assert err.msg() == 'connection refused'
		return
	}
	assert false
}

fn test_empty_batches_and_shutdown() {
	f := &Fake{
		replies: [Reply{
			status: 200
		}]
	}
	e := exporter_with(f, time.second)
	e.export([])!
	assert f.posts() == 0
	e.shutdown()!
	if _ := e.export(one_span()) {
		assert false, 'a shut-down exporter sent'
	}
	assert f.posts() == 0
}

fn test_it_is_a_span_exporter() {
	clear_env()
	e := trace.SpanExporter(Exporter.new()!)
	e.shutdown()!
}

// Package otlphttp sends telemetry to an OpenTelemetry collector over OTLP/HTTP,
// encoded as JSON.
module otlphttp

import net.http
import net.urllib
import os
import strconv
import time
import five07.otel
import five07.otel.sdk.trace

// default_endpoint is the collector's OTLP/HTTP address when none is set.
pub const default_endpoint = 'http://localhost:4318'

// default_timeout is how long one export may take when none is set.
pub const default_timeout = 10 * time.second

// Options set up an `Exporter`. What isn't given comes from the environment,
// then the specification's defaults.
@[params]
pub struct Options {
pub:
	// endpoint is the full traces URL, such as
	// `https://collector:4318/v1/traces`; by default
	// `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`, else `OTEL_EXPORTER_OTLP_ENDPOINT`
	// with `/v1/traces` added, else `http://localhost:4318/v1/traces`
	endpoint ?string
	// headers are sent with every export, over those of
	// `OTEL_EXPORTER_OTLP_HEADERS` and `OTEL_EXPORTER_OTLP_TRACES_HEADERS`,
	// such as an API key
	headers map[string]string
	// timeout bounds one export, its retry included; by default
	// `OTEL_EXPORTER_OTLP_TRACES_TIMEOUT`, else `OTEL_EXPORTER_OTLP_TIMEOUT`
	// (milliseconds), else 10 seconds
	timeout ?time.Duration
}

// Config is an exporter's settings once the options and the environment are
// read.
pub struct Config {
pub:
	url     string
	headers map[string]string
	timeout time.Duration
}

// Exporter sends spans to a collector: one POST of OTLP/JSON to the traces URL
// per batch. A batch the collector is too busy for (429, 502, 503, 504) is sent
// once more, after its `Retry-After` or a second, within the timeout; then it
// is lost, and `export` says why.
@[heap]
pub struct Exporter {
	config    Config
	transport Transport
	sleep     fn (time.Duration) = time.sleep
mut:
	stopped shared bool
}

// Exporter.new returns an exporter. A malformed endpoint is an error: sending
// elsewhere would lose the spans. Other malformed settings in the environment
// keep their defaults, with a warning on stderr.
pub fn Exporter.new(opts Options) !&Exporter {
	config, warnings := resolve(opts)!
	for w in warnings {
		eprintln('otel: ${w}')
	}
	return &Exporter{
		config:    config
		transport: HttpTransport{}
	}
}

// config returns the settings the exporter uses.
pub fn (e &Exporter) config() Config {
	return e.config
}

// export sends the spans as one request.
pub fn (e &Exporter) export(spans []trace.ReadOnlySpan) ! {
	if rlock e.stopped {
		e.stopped
	} {
		return error('the exporter is shut down')
	}
	if spans.len == 0 {
		return
	}
	body := encode_traces(spans, false)
	deadline := time.now().add(e.config.timeout)
	first := e.transport.post(e.config.url, e.config.headers, body, e.config.timeout)!
	if is_success(first.status) {
		return
	}
	if !is_retryable(first.status) {
		return error('the collector answered ${first.status}${first.reason()}')
	}
	wait := retry_delay(first.retry_after, time.now())
	left := deadline - time.now()
	if wait >= left {
		return error('the collector answered ${first.status}, and asked to wait longer than the timeout')
	}
	e.sleep(wait)
	second := e.transport.post(e.config.url, e.config.headers, body, deadline - time.now())!
	if !is_success(second.status) {
		return error('the collector answered ${first.status}, then ${second.status}${second.reason()}')
	}
}

// shutdown stops the exporter; later exports fail.
pub fn (e &Exporter) shutdown() ! {
	lock e.stopped {
		e.stopped = true
	}
}

fn is_success(status int) bool {
	return status >= 200 && status < 300
}

// is_retryable is the specification's list of statuses worth one more try.
fn is_retryable(status int) bool {
	return status in [429, 502, 503, 504]
}

// retry_delay reads `Retry-After`, seconds or an HTTP date; one second if it is
// missing or unreadable.
fn retry_delay(header string, now time.Time) time.Duration {
	h := header.trim_space()
	if h == '' {
		return time.second
	}
	if seconds := strconv.atoi(h) {
		return if seconds > 0 { seconds * time.second } else { 0 }
	}
	at := time.parse_rfc2822(h) or { return time.second }
	d := at - now
	return if d > 0 { d } else { 0 }
}

// Reply is what the exporter needs of a response.
struct Reply {
	status      int
	retry_after string
	body        string
}

// reason is a short look at the body, which collectors fill with the cause.
fn (r Reply) reason() string {
	b := r.body.trim_space()
	if b == '' {
		return ''
	}
	return ': ' + if b.len > 200 { b[..200] + '…' } else { b }
}

// Transport sends one request; tests put a fake in its place.
interface Transport {
	post(url string, headers map[string]string, body string, timeout time.Duration) !Reply
}

struct HttpTransport {}

fn (t HttpTransport) post(url string, headers map[string]string, body string, timeout time.Duration) !Reply {
	mut header := http.new_header(key: .content_type, value: 'application/json')
	for k, v in headers {
		header.add_custom(k, v)!
	}
	resp := http.fetch(
		url:           url
		method:        .post
		header:        header
		data:          body
		user_agent:    'OTel-OTLP-Exporter-V/${otel.version}'
		read_timeout:  i64(timeout)
		write_timeout: i64(timeout)
		// net.http counts attempts here, so 1 is one try; retries are ours
		max_retries:   1
	)!
	return Reply{
		status:      resp.status_code
		retry_after: resp.header.get(.retry_after) or { '' }
		body:        resp.body
	}
}

// resolve reads the options, then the environment, then the defaults. Only a
// malformed endpoint is an error; the rest are warnings.
fn resolve(opts Options) !(Config, []string) {
	mut warnings := []string{}
	url := if e := opts.endpoint {
		check_url(e, 'the endpoint')!
	} else if e := env('OTEL_EXPORTER_OTLP_TRACES_ENDPOINT') {
		check_url(e, 'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT')!
	} else if e := env('OTEL_EXPORTER_OTLP_ENDPOINT') {
		traces_url(check_url(e, 'OTEL_EXPORTER_OTLP_ENDPOINT')!)
	} else {
		traces_url(default_endpoint)
	}
	mut headers := map[string]string{}
	for name in ['OTEL_EXPORTER_OTLP_HEADERS', 'OTEL_EXPORTER_OTLP_TRACES_HEADERS'] {
		for k, v in parse_headers(name, env(name) or { '' }, mut warnings) {
			headers[k] = v
		}
	}
	for k, v in opts.headers {
		headers[k] = v
	}
	timeout := opts.timeout or {
		mut t := default_timeout
		for name in ['OTEL_EXPORTER_OTLP_TIMEOUT', 'OTEL_EXPORTER_OTLP_TRACES_TIMEOUT'] {
			if value := env(name) {
				ms := strconv.atoi(value) or { -1 }
				if ms > 0 {
					t = ms * time.millisecond
				} else {
					warnings << '${name}: `${value}` is not a number of milliseconds above 0; using ${t / time.millisecond}'
				}
			}
		}
		t
	}
	for name in ['OTEL_EXPORTER_OTLP_PROTOCOL', 'OTEL_EXPORTER_OTLP_TRACES_PROTOCOL'] {
		if p := env(name) {
			if p != 'http/json' {
				warnings << '${name}: `${p}` is not supported; this exporter sends http/json'
			}
		}
	}
	return Config{
		url:     url
		headers: headers
		timeout: timeout
	}, warnings
}

fn env(name string) ?string {
	v := os.getenv(name).trim_space()
	return if v == '' { none } else { v }
}

// check_url checks an endpoint is an http or https URL with a host.
fn check_url(s string, what string) !string {
	u := urllib.parse(s) or { return error('${what}: `${s}` is not a URL') }
	if u.scheme !in ['http', 'https'] || u.host == '' {
		return error('${what}: `${s}` is not an http or https URL with a host')
	}
	return s
}

// traces_url adds `v1/traces` to a base endpoint, after its own path:
// `http://host:4318/base` gives `http://host:4318/base/v1/traces`.
fn traces_url(base string) string {
	return if base.ends_with('/') { base + 'v1/traces' } else { base + '/v1/traces' }
}

// parse_headers reads `key=value,…`, values percent-encoded. A malformed entry
// is skipped with a warning naming it by position, not by its value, which may
// be a secret.
fn parse_headers(name string, s string, mut warnings []string) map[string]string {
	mut out := map[string]string{}
	if s.trim_space() == '' {
		return out
	}
	for i, entry in s.split(',') {
		if entry.trim_space() == '' {
			continue
		}
		eq := entry.index_u8(`=`)
		key := if eq > 0 { entry[..eq].trim_space() } else { '' }
		if key == '' {
			warnings << '${name}: entry ${i + 1} is not `key=value`; skipped'
			continue
		}
		value := urllib.path_unescape(entry[eq + 1..].trim_space()) or {
			warnings << '${name}: the value of `${key}` has a bad percent-encoding; skipped'
			continue
		}
		out[key] = value
	}
	return out
}

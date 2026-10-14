module otlphttp

// End to end over HTTP: the SDK and a batch processor send through this
// exporter and `net.http` to a fake collector, a `net.http.Server` in the test
// that records each request and answers as scripted.
import context
import json2
import net.http
import time
import five07.otel
import five07.otel.sdk.resource
import five07.otel.sdk.trace

// Collector answers each request with the next scripted status (200 after the
// script), and records what it got. With `hold`, each request waits on
// `release` before it is answered.
@[heap]
struct Collector {
	script  []int
	hold    bool
	entered chan bool = chan bool{cap: 100}
	release chan bool = chan bool{cap: 100}
mut:
	log shared CollectorLog
}

struct CollectorLog {
mut:
	requests []Received
}

struct Received {
	method  string
	path    string
	headers map[string]string
	body    string
}

fn (mut c Collector) handle(req http.Request) http.Response {
	if c.hold {
		c.entered <- true
		_ := <-c.release
	}
	n := lock c.log {
		c.log.requests << Received{
			method:  req.method.str()
			path:    req.url
			headers: {
				'content-type': req.header.get(.content_type) or { '' }
				'user-agent':   req.header.get(.user_agent) or { '' }
				'api-key':      req.header.get_custom('api-key') or { '' }
			}
			body:    req.data
		}
		c.log.requests.len
	}
	status := if n <= c.script.len { c.script[n - 1] } else { 200 }
	mut resp := http.Response{
		body: if status == 400 { '{"message":"bad span"}' } else { '{}' }
	}
	resp.set_status(http.status_from_int(status))
	if status == 503 {
		resp.header.add(.retry_after, '0')
	}
	return resp
}

fn (c &Collector) received() []Received {
	return rlock c.log {
		c.log.requests.clone()
	}
}

// span_names returns the names of the spans in each request's OTLP body.
fn (c &Collector) span_names() [][]string {
	mut out := [][]string{}
	for r in c.received() {
		mut names := []string{}
		root := json2.decode[json2.Any](r.body) or { panic(err) }
		for rs in (root.as_map()['resourceSpans'] or { panic('') }).as_array() {
			for ss in (rs.as_map()['scopeSpans'] or { panic('') }).as_array() {
				for s in (ss.as_map()['spans'] or { panic('') }).as_array() {
					names << (s.as_map()['name'] or { '' }).str()
				}
			}
		}
		out << names
	}
	return out
}

struct Running {
	collector &Collector
	server    &http.Server
	url       string
}

fn start(c &Collector) Running {
	mut server := &http.Server{
		addr:                 '127.0.0.1:0'
		handler:              c
		show_startup_message: false
		accept_timeout:       50 * time.millisecond
	}
	spawn fn (mut s http.Server) {
		s.listen_and_serve()
	}(mut server)
	server.wait_till_running() or { panic(err) }
	return Running{
		collector: c
		server:    server
		url:       'http://${server.addr}/v1/traces'
	}
}

fn (r Running) stop() {
	mut s := r.server
	s.stop()
}

struct Pipeline {
	provider  &trace.TracerProvider
	processor &trace.BatchSpanProcessor
	tracer    otel.Tracer
}

fn pipeline(url string, opts trace.BatchOptions) !Pipeline {
	exporter := Exporter.new(
		endpoint: url
		headers:  {
			'api-key': 'secret-key'
		}
		timeout:  5 * time.second
	)!
	processor := trace.BatchSpanProcessor.new(exporter, opts)
	provider := trace.TracerProvider.new(
		resource:     resource.Resource.new([otel.string_attr('service.name', 'blog')],
			'')
		sampler:      trace.always_on_sampler()
		id_generator: trace.SequentialIdGenerator.new()
		processors:   [processor]
		limits:       trace.SpanLimits{}
	)!
	return Pipeline{provider, processor, provider.tracer('five07.vgraph')}
}

fn (p Pipeline) spans(names ...string) {
	for name in names {
		_, span := p.tracer.start(context.background(), name)
		span.end()
	}
}

fn eventually(cond fn () bool) bool {
	for _ in 0 .. 3000 {
		if cond() {
			return true
		}
		time.sleep(time.millisecond)
	}
	return cond()
}

fn test_full_batches_go_out_and_the_rest_at_shutdown() {
	c := &Collector{}
	r := start(c)
	defer {
		r.stop()
	}
	p := pipeline(r.url, max_export_batch_size: 2, schedule_delay: time.hour)!
	p.spans('a', 'b', 'c', 'd', 'e')
	assert eventually(fn [c] () bool {
		return c.received().len == 2
	})
	p.provider.shutdown()!
	assert c.span_names() == [['a', 'b'], ['c', 'd'], ['e']]
	got := c.received()[0]
	assert got.method == 'POST'
	assert got.path == '/v1/traces'
	assert got.headers['content-type'] == 'application/json'
	assert got.headers['api-key'] == 'secret-key'
	assert got.headers['user-agent'].starts_with('OTel-OTLP-Exporter-V/')
}

fn test_a_part_batch_goes_out_after_the_delay() {
	c := &Collector{}
	r := start(c)
	defer {
		r.stop()
	}
	p := pipeline(r.url, schedule_delay: 100 * time.millisecond)!
	p.spans('alone')
	assert eventually(fn [c] () bool {
		return c.received().len == 1
	})
	assert c.span_names() == [['alone']]
	p.provider.shutdown()!
}

fn test_a_503_is_retried_and_the_spans_arrive_once() {
	c := &Collector{
		script: [503]
	}
	r := start(c)
	defer {
		r.stop()
	}
	p := pipeline(r.url, schedule_delay: time.hour)!
	p.spans('a', 'b')
	p.provider.shutdown()!
	got := c.received()
	assert got.len == 2
	assert got[0].body == got[1].body
	assert c.span_names()[1] == ['a', 'b']
}

@[heap]
struct Errors {
mut:
	msgs shared []string
}

fn test_a_400_is_reported_and_not_retried() {
	c := &Collector{
		script: [400]
	}
	r := start(c)
	defer {
		r.stop()
	}
	errs := &Errors{}
	p := pipeline(r.url,
		schedule_delay: time.hour
		on_error:       fn [errs] (err IError) {
			lock errs.msgs {
				errs.msgs << err.msg()
			}
		}
	)!
	p.spans('a')
	p.provider.shutdown()!
	assert c.received().len == 1
	assert rlock errs.msgs {
		errs.msgs.clone()
	} == ['the collector answered 400: {"message":"bad span"}']
}

fn test_a_slow_collector_costs_spans_not_time() {
	c := &Collector{
		hold: true
	}
	r := start(c)
	defer {
		r.stop()
	}
	p := pipeline(r.url, max_queue_size: 3, max_export_batch_size: 1, schedule_delay: time.hour)!
	p.spans('first')
	select {
		_ := <-c.entered {
		}
		3 * time.second {
			assert false, 'the first span never reached the collector'
		}
	}
	// the exporter is held at the collector: three spans fill the queue, the
	// rest are dropped, and none of it waits
	started := time.now()
	p.spans('q1', 'q2', 'q3', 'x1', 'x2')
	assert time.since(started) < 500 * time.millisecond
	assert p.processor.dropped() == 2
	for _ in 0 .. 10 {
		c.release <- true
	}
	p.provider.shutdown()!
	assert c.span_names() == [['first'], ['q1'], ['q2'], ['q3']]
}

fn test_a_collector_that_is_gone_is_reported() {
	errs := &Errors{}
	p := pipeline('http://127.0.0.1:1/v1/traces',
		schedule_delay: time.hour
		on_error:       fn [errs] (err IError) {
			lock errs.msgs {
				errs.msgs << err.msg()
			}
		}
	)!
	p.spans('lost')
	p.provider.shutdown()!
	assert rlock errs.msgs {
		errs.msgs.len
	} == 1
}

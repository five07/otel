module otel

import context

fn test_a_library_given_no_provider_records_nothing() {
	provider := noop_tracer_provider()
	tracer := provider.tracer('five07.vgraph', version: '0.1.0')
	ctx := context.background()
	ctx2, span := tracer.start(ctx, 'SELECT users', kind: .client)
	assert !span.is_recording()
	assert !span.span_context().is_valid()
	assert !span_from_context(ctx2).span_context().is_valid()
	// every call is taken, and does nothing
	span.set_name('SELECT posts')
	span.set_attributes(string_attr('db.collection.name', 'users'), int_attr('n', 1))
	span.add_event('retry', attributes: [int_attr('attempt', 2)])
	span.add_link(Link{})
	span.set_status(code: .error, description: 'timed out')
	span.record_error(error('no such table'), with_message: true)
	span.end()
	span.end()
	assert !span.is_recording()
}

fn test_a_noop_span_keeps_its_span_context() {
	sc := SpanContext{
		trace_id: TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
		span_id:  SpanId.from_hex('00f067aa0ba902b7')!
		flags:    TraceFlags{}.with_sampled(true)
		remote:   true
	}
	span := Span(NoopSpan{
		context: sc
	})
	span.end()
	assert span.span_context() == sc
	assert !span.is_recording()
}

// Recorder is a span that keeps what it is given, to show that the API's
// options reach an implementation as the caller wrote them.
@[heap]
struct Recorder {
mut:
	calls shared []string
}

fn (r &Recorder) log(s string) {
	lock r.calls {
		r.calls << s
	}
}

fn (r &Recorder) span_context() SpanContext {
	return SpanContext{}
}

fn (r &Recorder) is_recording() bool {
	return true
}

fn (r &Recorder) set_name(name string) {
	r.log('name ${name}')
}

fn (r &Recorder) set_attributes(attrs ...KeyValue) {
	r.log('attrs ${attrs.map(it.key).join(',')}')
}

fn (r &Recorder) add_event(name string, opts EventOptions) {
	r.log('event ${name} ${opts.attributes.len}')
}

fn (r &Recorder) add_link(link Link) {
	r.log('link')
}

fn (r &Recorder) set_status(status Status) {
	r.log('status ${status.code} ${status.description}')
}

fn (r &Recorder) record_error(err IError, opts ErrorOptions) {
	r.log('error ${err.msg()} ${opts.with_message}')
}

fn (r &Recorder) end(opts EndOptions) {
	r.log('end ${opts.end != none}')
}

fn test_span_calls_reach_an_implementation() {
	r := &Recorder{}
	span := Span(r)
	span.set_name('n')
	span.set_attributes(string_attr('a', '1'), string_attr('b', '2'))
	span.set_attributes()
	span.add_event('e')
	span.add_link(Link{})
	span.set_status(code: .ok)
	span.record_error(error('boom'))
	span.end()
	calls := rlock r.calls {
		r.calls.clone()
	}
	assert calls == ['name n', 'attrs a,b', 'attrs ', 'event e 0', 'link', 'status ok ',
		'error boom false', 'end false']
}

fn test_noop_span_records_nothing() {
	span := noop_span()
	assert !span.is_recording()
	assert !span.span_context().is_valid()
	span.end()
}

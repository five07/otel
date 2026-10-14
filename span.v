module otel

import time

// SpanKind says what part a span plays in a call between services, which
// backends use to draw the call across them.
pub enum SpanKind {
	// internal is work within a service, the default
	internal
	// server is a service handling a request from another
	server
	// client is a request to another service, or to a database
	client
	// producer is a message sent to be handled later, such as onto a queue
	producer
	// consumer is the handling of a message a producer sent
	consumer
}

// StatusCode is how a span's operation ended.
pub enum StatusCode {
	// unset is the default: no one said, which backends take as success
	unset
	// ok is success, set on purpose; it overrides an error, and nothing overrides it
	ok
	// error is a failure
	error
}

// Status is a span's status: its code, and for an error, a description. The
// description is dropped for any other code, as the specification says. It
// is free text, so it should not quote values the span mustn't carry.
@[params]
pub struct Status {
pub:
	code        StatusCode
	description string
}

// Link points from a span to another span that isn't its parent, such as each
// of the messages a batch job handles, with attributes about the link.
pub struct Link {
pub:
	span_context SpanContext
	attributes   []KeyValue
}

// SpanStartOptions are a span's settings at its start. A span's parent comes
// from the context it is started with, unless `new_root` is set.
@[params]
pub struct SpanStartOptions {
pub:
	kind       SpanKind
	attributes []KeyValue
	links      []Link
	// start is when the span started, if not now: for work that is reported
	// after it ran, such as a statement's span, built from its start time
	start ?time.Time
	// new_root starts a trace of its own, ignoring any parent in the context
	new_root bool
}

// EndOptions are a span's settings at its end.
@[params]
pub struct EndOptions {
pub:
	// end is when the span ended, if not now
	end ?time.Time
}

// EventOptions are an event's attributes, and its time if not now.
@[params]
pub struct EventOptions {
pub:
	attributes []KeyValue
	timestamp  ?time.Time
}

// ErrorOptions are the settings of `Span.record_error`. The error's message is
// left out unless `with_message` is set, since messages can quote the values
// that failed.
@[params]
pub struct ErrorOptions {
pub:
	attributes   []KeyValue
	timestamp    ?time.Time
	with_message bool
}

// Span is one operation within a trace, from its start to its `end`. Its
// methods may be called from any thread, and do nothing once it has ended. A
// span that isn't recording (sampled out, or from the no-op API) takes every
// call and keeps nothing.
pub interface Span {
	// span_context identifies the span, to children and to other services
	span_context() SpanContext
	// is_recording tells whether the span keeps what it is given, so a caller
	// can skip work that only builds attributes
	is_recording() bool
	// set_name renames the span, such as once a route is known
	set_name(name string)
	// set_attributes sets attributes, replacing any with the same key
	set_attributes(attrs ...KeyValue)
	// add_event records something that happened at a moment in the span
	add_event(name string, opts EventOptions)
	// add_link links the span to another, after its start
	add_link(link Link)
	// set_status sets how the operation ended: `set_status(code: .error)`
	set_status(status Status)
	// record_error adds an `exception` event for `err`; it does not set the
	// status, which is the caller's to decide
	record_error(err IError, opts ErrorOptions)
	// end ends the span; later calls to it, and to the other methods, do nothing
	end(opts EndOptions)
}

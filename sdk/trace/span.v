module trace

import time
import five07.otel
import five07.otel.sdk.resource
import five07.otel.semconv

// SpanLimits bound what one span keeps, so a loop that adds attributes or
// events can't grow a span without end. What goes over a limit is dropped and
// counted, and the counts are exported with the span.
pub struct SpanLimits {
pub:
	attribute_count      int = 128
	event_count          int = 128
	link_count           int = 128
	attributes_per_event int = 128
	attributes_per_link  int = 128
}

// InstrumentationScope names the code that made a span: the library a
// `Tracer` was asked for.
pub struct InstrumentationScope {
pub:
	name       string
	version    string
	schema_url string
	attributes []otel.KeyValue
}

// Event is something that happened at a moment in a span.
pub struct Event {
pub:
	name               string
	time_ns            i64
	attributes         []otel.KeyValue
	dropped_attributes int
}

// Link is a span's link to another span, with its attributes as kept.
pub struct Link {
pub:
	span_context       otel.SpanContext
	attributes         []otel.KeyValue
	dropped_attributes int
}

// ReadOnlySpan is a span's data at one moment, which no longer changes: what
// processors and exporters get. Times are unix nanoseconds; `end_ns` is 0 for a
// span that hasn't ended.
pub struct ReadOnlySpan {
pub:
	name               string
	span_context       otel.SpanContext
	parent             otel.SpanContext
	kind               otel.SpanKind
	start_ns           i64
	end_ns             i64
	attributes         []otel.KeyValue
	dropped_attributes int
	events             []Event
	dropped_events     int
	links              []Link
	dropped_links      int
	status             otel.Status
	scope              InstrumentationScope
	resource           resource.Resource
}

// is_child_of tells whether the span's parent is `other`: the same trace, and
// `other`'s span id as its parent's.
pub fn (s ReadOnlySpan) is_child_of(other ReadOnlySpan) bool {
	return s.parent.is_valid() && s.parent.trace_id == other.span_context.trace_id
		&& s.parent.span_id == other.span_context.span_id
}

// attribute returns the value of the attribute `key`, or none.
pub fn (s ReadOnlySpan) attribute(key string) ?otel.Value {
	for kv in s.attributes {
		if kv.key == key {
			return kv.value
		}
	}
	return none
}

// Anchor ties the monotonic clock to the wall clock at one moment, the start of
// a trace in this process. Its spans take their times from it: on one timeline
// with the monotonic clock's precision, so a child never seems to start before
// or end after its parent, as two readings of a coarse wall clock can make it
// seem. Drift from the wall clock is bounded by how long the trace runs.
struct Anchor {
	wall_ns i64
	mono    u64
}

fn new_anchor() Anchor {
	return Anchor{
		wall_ns: time.now().unix_nano()
		mono:    time.sys_mono_now()
	}
}

// now_ns is the time now, in unix nanoseconds, on the anchor's timeline.
fn (a Anchor) now_ns() i64 {
	return a.wall_ns + i64(time.sys_mono_now() - a.mono)
}

// RecordingSpan is the SDK's span: it keeps what it is given until it ends,
// then hands its data to `on_end`. Its methods may be called from any thread.
@[heap]
pub struct RecordingSpan {
	context  otel.SpanContext
	parent   otel.SpanContext
	kind     otel.SpanKind
	start_ns i64
	anchor   Anchor
	scope    InstrumentationScope
	resource resource.Resource
	limits   SpanLimits
	on_end   fn (ReadOnlySpan) @[required]
mut:
	state shared SpanState
}

struct SpanState {
mut:
	name               string
	attributes         []otel.KeyValue
	dropped_attributes int
	events             []Event
	dropped_events     int
	links              []Link
	dropped_links      int
	status             otel.Status
	end_ns             i64
	ended              bool
}

// SpanConfig is what the tracer knows when it starts a span.
struct SpanConfig {
	name       string
	context    otel.SpanContext
	parent     otel.SpanContext
	kind       otel.SpanKind
	attributes []otel.KeyValue
	links      []otel.Link
	start      ?time.Time
	// anchor is the parent's, for a parent recording in this process
	anchor   ?Anchor
	scope    InstrumentationScope
	resource resource.Resource
	limits   SpanLimits
	on_end   fn (ReadOnlySpan) @[required]
}

fn new_recording_span(c SpanConfig) &RecordingSpan {
	anchor := c.anchor or { new_anchor() }
	start_ns := if t := c.start { t.unix_nano() } else { anchor.now_ns() }
	s := &RecordingSpan{
		context:  c.context
		parent:   c.parent
		kind:     c.kind
		start_ns: start_ns
		anchor:   anchor
		scope:    c.scope
		resource: c.resource
		limits:   c.limits
		on_end:   c.on_end
		state:    SpanState{
			name: c.name
		}
	}
	s.set_attributes(...c.attributes)
	for link in c.links {
		s.add_link(link)
	}
	return s
}

// span_context returns the span's ids, flags and trace state.
pub fn (s &RecordingSpan) span_context() otel.SpanContext {
	return s.context
}

// is_recording is true until the span ends.
pub fn (s &RecordingSpan) is_recording() bool {
	return rlock s.state {
		!s.state.ended
	}
}

// set_name renames the span.
pub fn (s &RecordingSpan) set_name(name string) {
	lock s.state {
		if !s.state.ended {
			s.state.name = name
		}
	}
}

// set_attributes sets each attribute, replacing the value of a key the span
// has. A new key past the limit is dropped and counted; an empty key is
// dropped.
pub fn (s &RecordingSpan) set_attributes(attrs ...otel.KeyValue) {
	lock s.state {
		if s.state.ended {
			return
		}
		for kv in attrs {
			if kv.key == '' {
				continue
			}
			i := index_of(s.state.attributes, kv.key)
			if i >= 0 {
				s.state.attributes[i] = kv
			} else if s.state.attributes.len < s.limits.attribute_count {
				s.state.attributes << kv
			} else {
				s.state.dropped_attributes++
			}
		}
	}
}

// add_event records an event, at its timestamp or now. Past the limit it is
// dropped and counted.
pub fn (s &RecordingSpan) add_event(name string, opts otel.EventOptions) {
	at := if t := opts.timestamp { t.unix_nano() } else { s.anchor.now_ns() }
	attrs, dropped := limit_attributes(opts.attributes, s.limits.attributes_per_event)
	lock s.state {
		if s.state.ended {
			return
		}
		if s.state.events.len >= s.limits.event_count {
			s.state.dropped_events++
			return
		}
		s.state.events << Event{
			name:               name
			time_ns:            at
			attributes:         attrs
			dropped_attributes: dropped
		}
	}
}

// add_link links the span to another. A link to an invalid span context is
// ignored; past the limit it is dropped and counted.
pub fn (s &RecordingSpan) add_link(link otel.Link) {
	if !link.span_context.is_valid() {
		return
	}
	attrs, dropped := limit_attributes(link.attributes, s.limits.attributes_per_link)
	lock s.state {
		if s.state.ended {
			return
		}
		if s.state.links.len >= s.limits.link_count {
			s.state.dropped_links++
			return
		}
		s.state.links << Link{
			span_context:       link.span_context
			attributes:         attrs
			dropped_attributes: dropped
		}
	}
}

// set_status sets the span's status, as the specification orders: `ok` is
// final, `unset` is ignored, and a description is kept only with `error`.
pub fn (s &RecordingSpan) set_status(status otel.Status) {
	if status.code == .unset {
		return
	}
	lock s.state {
		if s.state.ended || s.state.status.code == .ok {
			return
		}
		s.state.status = otel.Status{
			code:        status.code
			description: if status.code == .error { status.description } else { '' }
		}
	}
}

// record_error adds an `exception` event with `exception.type`, and
// `exception.message` only if asked: a message can quote the values that
// failed. It leaves the status alone.
pub fn (s &RecordingSpan) record_error(err IError, opts otel.ErrorOptions) {
	mut attrs := [otel.string_attr(semconv.exception_type, err.type_name())]
	if opts.with_message {
		attrs << otel.string_attr(semconv.exception_message, err.msg())
	}
	attrs << opts.attributes
	s.add_event(semconv.exception_event, attributes: attrs, timestamp: opts.timestamp)
}

// end ends the span, at `opts.end` or now, and hands its data to `on_end`.
// Only the first call does anything.
pub fn (s &RecordingSpan) end(opts otel.EndOptions) {
	end_ns := if t := opts.end { t.unix_nano() } else { s.anchor.now_ns() }
	ended_now := lock s.state {
		if s.state.ended {
			false
		} else {
			s.state.ended = true
			s.state.end_ns = end_ns
			true
		}
	}
	if ended_now {
		s.on_end(s.read_only())
	}
}

// read_only returns the span's data as it is now.
pub fn (s &RecordingSpan) read_only() ReadOnlySpan {
	return rlock s.state {
		ReadOnlySpan{
			name:               s.state.name
			span_context:       s.context
			parent:             s.parent
			kind:               s.kind
			start_ns:           s.start_ns
			end_ns:             s.state.end_ns
			attributes:         s.state.attributes.clone()
			dropped_attributes: s.state.dropped_attributes
			events:             s.state.events.clone()
			dropped_events:     s.state.dropped_events
			links:              s.state.links.clone()
			dropped_links:      s.state.dropped_links
			status:             s.state.status
			scope:              s.scope
			resource:           s.resource
		}
	}
}

fn index_of(attrs []otel.KeyValue, key string) int {
	for i, kv in attrs {
		if kv.key == key {
			return i
		}
	}
	return -1
}

// limit_attributes keeps the last value of each key, in first-seen order, up to
// `max` keys, and counts the keys dropped. Empty keys are dropped uncounted.
fn limit_attributes(attrs []otel.KeyValue, max int) ([]otel.KeyValue, int) {
	mut kept := []otel.KeyValue{}
	mut dropped := 0
	for kv in attrs {
		if kv.key == '' {
			continue
		}
		i := index_of(kept, kv.key)
		if i >= 0 {
			kept[i] = kv
		} else if kept.len < max {
			kept << kv
		} else {
			dropped++
		}
	}
	return kept, dropped
}

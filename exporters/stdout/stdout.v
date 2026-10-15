// Package stdout writes telemetry as JSON lines to standard output, for local
// development and tests.
module stdout

import io
import os
import strings
import time
import five07.otel
import five07.otel.sdk.trace
import five07.otel.exporters.internal.jsonw { Arr, Node, Obj, Raw, float_node, int_node, str_node }

// Options set up an `Exporter`.
@[params]
pub struct Options {
pub:
	// pretty writes each span indented over several lines, not one line
	pretty bool
	// resource adds the resource's attributes to every span
	resource bool
	// writer is where spans go; by default standard output
	writer ?io.Writer
}

// Exporter writes each span as a JSON object: by default one line per span,
// which `jq` and log tools read. Its fields: `name`, `trace_id`, `span_id`,
// `parent_span_id` (none for a root), `trace_state`, `kind`, `start_time` and
// `end_time` (RFC 3339, UTC, nanoseconds), `duration_ms`, `status`,
// `attributes`, `events`, `links`, `scope`, and the dropped counts when not 0.
@[heap]
pub struct Exporter {
	pretty   bool
	resource bool
mut:
	out shared Output
}

struct Output {
mut:
	w       io.Writer
	stopped bool
}

// Exporter.new returns an exporter writing to `opts.writer`, or standard output.
pub fn Exporter.new(opts Options) &Exporter {
	return &Exporter{
		pretty:   opts.pretty
		resource: opts.resource
		out:      Output{
			w: opts.writer or { io.Writer(os.stdout()) }
		}
	}
}

// export writes the spans, in order.
pub fn (e &Exporter) export(spans []trace.ReadOnlySpan) ! {
	mut text := strings.new_builder(512 * spans.len)
	for s in spans {
		text.write_string(jsonw.encode(span_node(s, e.resource), e.pretty))
		text.write_u8(`\n`)
	}
	bytes := text.str().bytes()
	lock e.out {
		if e.out.stopped {
			return error('the exporter is shut down')
		}
		mut written := 0
		for written < bytes.len {
			written += e.out.w.write(bytes[written..])!
		}
	}
}

// shutdown stops the exporter; later exports fail.
pub fn (e &Exporter) shutdown() ! {
	lock e.out {
		e.out.stopped = true
	}
}

fn span_node(s trace.ReadOnlySpan, with_resource bool) Node {
	mut o := Obj{}
	o.add('name', str_node(s.name))
	o.add('trace_id', str_node(s.span_context.trace_id.hex()))
	o.add('span_id', str_node(s.span_context.span_id.hex()))
	if s.parent.is_valid() {
		o.add('parent_span_id', str_node(s.parent.span_id.hex()))
	}
	state := s.span_context.state.str()
	if state != '' {
		o.add('trace_state', str_node(state))
	}
	o.add('kind', str_node(s.kind.str()))
	o.add('start_time', str_node(format_time(s.start_ns)))
	o.add('end_time', str_node(format_time(s.end_ns)))
	o.add('duration_ms', Raw{'${f64(s.end_ns - s.start_ns) / 1e6:.3f}'})
	mut status := Obj{}
	status.add('code', str_node(s.status.code.str()))
	if s.status.description != '' {
		status.add('description', str_node(s.status.description))
	}
	o.add('status', status)
	o.add('attributes', attributes_node(s.attributes))
	if s.dropped_attributes > 0 {
		o.add('dropped_attributes', int_node(s.dropped_attributes))
	}
	o.add('events', Arr{s.events.map(event_node(it))})
	if s.dropped_events > 0 {
		o.add('dropped_events', int_node(s.dropped_events))
	}
	o.add('links', Arr{s.links.map(link_node(it))})
	if s.dropped_links > 0 {
		o.add('dropped_links', int_node(s.dropped_links))
	}
	mut scope := Obj{}
	scope.add('name', str_node(s.scope.name))
	if s.scope.version != '' {
		scope.add('version', str_node(s.scope.version))
	}
	o.add('scope', scope)
	if with_resource {
		o.add('resource', attributes_node(s.resource.attributes()))
	}
	return o
}

fn event_node(e trace.Event) Node {
	mut o := Obj{}
	o.add('name', str_node(e.name))
	o.add('time', str_node(format_time(e.time_ns)))
	o.add('attributes', attributes_node(e.attributes))
	if e.dropped_attributes > 0 {
		o.add('dropped_attributes', int_node(e.dropped_attributes))
	}
	return o
}

fn link_node(l trace.Link) Node {
	mut o := Obj{}
	o.add('trace_id', str_node(l.span_context.trace_id.hex()))
	o.add('span_id', str_node(l.span_context.span_id.hex()))
	o.add('attributes', attributes_node(l.attributes))
	if l.dropped_attributes > 0 {
		o.add('dropped_attributes', int_node(l.dropped_attributes))
	}
	return o
}

fn attributes_node(attrs []otel.KeyValue) Node {
	mut o := Obj{}
	for kv in attrs {
		o.add(kv.key, value_node(kv.value))
	}
	return o
}

fn value_node(v otel.Value) Node {
	return match v {
		string { str_node(v) }
		bool { Raw{v.str()} }
		i64 { int_node(v) }
		f64 { float_node(v) }
		[]string { Arr{v.map(str_node(it))} }
		[]bool { Arr{v.map(Node(Raw{it.str()}))} }
		[]i64 { Arr{v.map(int_node(it))} }
		[]f64 { Arr{v.map(float_node(it))} }
	}
}

fn format_time(ns i64) string {
	return time.unix_nano(ns).format_rfc3339_nano()
}

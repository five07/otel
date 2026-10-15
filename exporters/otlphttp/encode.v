module otlphttp

import five07.otel
import five07.otel.sdk.resource
import five07.otel.sdk.trace
import five07.otel.exporters.internal.jsonw { Arr, Node, Obj, Raw, float_node, int_node, str_node }

// span_flags_has_remote_mask and span_flags_is_remote_mask are the bits of a
// span's (or link's) `flags` above the W3C trace flags that say whether its
// parent (or the linked span) came from another process.
const span_flags_has_remote_mask = u32(0x100)
const span_flags_is_remote_mask = u32(0x200)

// encode_traces writes `spans` as an OTLP/JSON `ExportTraceServiceRequest`, the
// body of a POST to `/v1/traces`: grouped by resource, then by instrumentation
// scope, in the order they first appear. As the OTLP specification asks, ids
// are hex, 64-bit integers (times, `intValue`) are strings, enums are numbers,
// and fields at their default (empty, zero) are left out. `pretty` indents it.
pub fn encode_traces(spans []trace.ReadOnlySpan, pretty bool) string {
	return jsonw.encode(request_node(spans), pretty)
}

struct ScopeGroup {
	scope trace.InstrumentationScope
mut:
	spans []trace.ReadOnlySpan
}

struct ResourceGroup {
	resource resource.Resource
mut:
	scopes []ScopeGroup
}

fn request_node(spans []trace.ReadOnlySpan) Node {
	mut groups := []ResourceGroup{}
	for s in spans {
		mut ri := groups.len
		for i, g in groups {
			if same_resource(g.resource, s.resource) {
				ri = i
				break
			}
		}
		if ri == groups.len {
			groups << ResourceGroup{
				resource: s.resource
			}
		}
		mut si := groups[ri].scopes.len
		for i, sg in groups[ri].scopes {
			if sg.scope == s.scope {
				si = i
				break
			}
		}
		if si == groups[ri].scopes.len {
			groups[ri].scopes << ScopeGroup{
				scope: s.scope
			}
		}
		groups[ri].scopes[si].spans << s
	}
	mut root := Obj{}
	root.add('resourceSpans', Arr{groups.map(resource_spans_node(it))})
	return root
}

fn same_resource(a resource.Resource, b resource.Resource) bool {
	return a.schema_url == b.schema_url && a.attributes() == b.attributes()
}

fn resource_spans_node(g ResourceGroup) Node {
	mut o := Obj{}
	mut r := Obj{}
	add_attributes(mut r, 'attributes', g.resource.attributes())
	o.add('resource', r)
	o.add('scopeSpans', Arr{g.scopes.map(scope_spans_node(it))})
	add_string(mut o, 'schemaUrl', g.resource.schema_url)
	return o
}

fn scope_spans_node(g ScopeGroup) Node {
	mut o := Obj{}
	mut scope := Obj{}
	add_string(mut scope, 'name', g.scope.name)
	add_string(mut scope, 'version', g.scope.version)
	add_attributes(mut scope, 'attributes', g.scope.attributes)
	o.add('scope', scope)
	o.add('spans', Arr{g.spans.map(span_node(it))})
	add_string(mut o, 'schemaUrl', g.scope.schema_url)
	return o
}

fn span_node(s trace.ReadOnlySpan) Node {
	mut o := Obj{}
	o.add('traceId', str_node(s.span_context.trace_id.hex()))
	o.add('spanId', str_node(s.span_context.span_id.hex()))
	add_string(mut o, 'traceState', s.span_context.state.str())
	if s.parent.is_valid() {
		o.add('parentSpanId', str_node(s.parent.span_id.hex()))
	}
	o.add('flags', int_node(flags(s.span_context.flags, s.parent.remote)))
	o.add('name', str_node(s.name))
	o.add('kind', int_node(kind_number(s.kind)))
	o.add('startTimeUnixNano', str_node(s.start_ns.str()))
	o.add('endTimeUnixNano', str_node(s.end_ns.str()))
	add_attributes(mut o, 'attributes', s.attributes)
	add_count(mut o, 'droppedAttributesCount', s.dropped_attributes)
	if s.events.len > 0 {
		o.add('events', Arr{s.events.map(event_node(it))})
	}
	add_count(mut o, 'droppedEventsCount', s.dropped_events)
	if s.links.len > 0 {
		o.add('links', Arr{s.links.map(link_node(it))})
	}
	add_count(mut o, 'droppedLinksCount', s.dropped_links)
	mut status := Obj{}
	add_string(mut status, 'message', s.status.description)
	if s.status.code != .unset {
		// OTLP numbers them as otel does: unset 0, ok 1, error 2
		status.add('code', int_node(int(s.status.code)))
	}
	o.add('status', status)
	return o
}

fn event_node(e trace.Event) Node {
	mut o := Obj{}
	o.add('timeUnixNano', str_node(e.time_ns.str()))
	o.add('name', str_node(e.name))
	add_attributes(mut o, 'attributes', e.attributes)
	add_count(mut o, 'droppedAttributesCount', e.dropped_attributes)
	return o
}

fn link_node(l trace.Link) Node {
	mut o := Obj{}
	o.add('traceId', str_node(l.span_context.trace_id.hex()))
	o.add('spanId', str_node(l.span_context.span_id.hex()))
	add_string(mut o, 'traceState', l.span_context.state.str())
	add_attributes(mut o, 'attributes', l.attributes)
	add_count(mut o, 'droppedAttributesCount', l.dropped_attributes)
	o.add('flags', int_node(flags(l.span_context.flags, l.span_context.remote)))
	return o
}

// flags is the W3C trace flags, with the bits saying whether the parent (or
// linked span) is known to be remote, and is.
fn flags(f otel.TraceFlags, remote bool) i64 {
	mut bits := u32(f.bits) | span_flags_has_remote_mask
	if remote {
		bits |= span_flags_is_remote_mask
	}
	return i64(bits)
}

// kind_number is OTLP's number for a kind: its enum starts with UNSPECIFIED at
// 0, so internal is 1.
fn kind_number(k otel.SpanKind) i64 {
	return match k {
		.internal { 1 }
		.server { 2 }
		.client { 3 }
		.producer { 4 }
		.consumer { 5 }
	}
}

fn add_string(mut o Obj, key string, value string) {
	if value != '' {
		o.add(key, str_node(value))
	}
}

fn add_count(mut o Obj, key string, n int) {
	if n > 0 {
		o.add(key, int_node(n))
	}
}

fn add_attributes(mut o Obj, key string, attrs []otel.KeyValue) {
	if attrs.len > 0 {
		o.add(key, Arr{attrs.map(key_value_node(it))})
	}
}

fn key_value_node(kv otel.KeyValue) Node {
	mut o := Obj{}
	o.add('key', str_node(kv.key))
	o.add('value', any_value_node(kv.value))
	return o
}

// any_value_node writes OTLP's `AnyValue`: one field named for the type.
fn any_value_node(v otel.Value) Node {
	mut o := Obj{}
	match v {
		string { o.add('stringValue', str_node(v)) }
		bool { o.add('boolValue', Raw{v.str()}) }
		i64 { o.add('intValue', str_node(v.str())) }
		f64 { o.add('doubleValue', float_node(v)) }
		[]string { o.add('arrayValue', array_node(v.map(any_value_node(otel.Value(it))))) }
		[]bool { o.add('arrayValue', array_node(v.map(any_value_node(otel.Value(it))))) }
		[]i64 { o.add('arrayValue', array_node(v.map(any_value_node(otel.Value(it))))) }
		[]f64 { o.add('arrayValue', array_node(v.map(any_value_node(otel.Value(it))))) }
	}
	return o
}

fn array_node(values []Node) Node {
	mut o := Obj{}
	if values.len > 0 {
		o.add('values', Arr{values})
	}
	return o
}

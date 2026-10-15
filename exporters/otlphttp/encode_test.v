module otlphttp

import json2
import math
import os
import five07.otel
import five07.otel.sdk.resource
import five07.otel.sdk.trace

fn sc(trace_hex string, span_hex string) otel.SpanContext {
	return otel.SpanContext{
		trace_id: otel.TraceId.from_hex(trace_hex) or { panic(err) }
		span_id:  otel.SpanId.from_hex(span_hex) or { panic(err) }
		flags:    otel.TraceFlags{}.with_sampled(true)
	}
}

// the span of the OTLP repository's examples/trace.json
fn example_span() trace.ReadOnlySpan {
	return trace.ReadOnlySpan{
		name:         "I'm a server span"
		span_context: sc('5b8efff798038103d269b633813fc60c', 'eee19b7ec3c1b174')
		parent:       sc('5b8efff798038103d269b633813fc60c', 'eee19b7ec3c1b173')
		kind:         .server
		start_ns:     1544712660000000000
		end_ns:       1544712661000000000
		attributes:   [otel.string_attr('my.span.attr', 'some value')]
		scope:        trace.InstrumentationScope{
			name:       'my.library'
			version:    '1.0.0'
			attributes: [otel.string_attr('my.scope.attribute', 'some scope attribute')]
		}
		resource:     resource.Resource.new([otel.string_attr('service.name', 'my.service')],
			'')
	}
}

// contains tells whether every field of `want` is in `got` with the same value,
// hex ids compared without case; `got` may have more fields.
fn contains(got json2.Any, want json2.Any, path string) ! {
	match want {
		map[string]json2.Any {
			g := got.as_map()
			for k, v in want {
				contains(g[k] or { return error('${path}.${k} is missing') }, v, '${path}.${k}')!
			}
		}
		[]json2.Any {
			g := got.as_array()
			if g.len != want.len {
				return error('${path} has ${g.len} items, not ${want.len}')
			}
			for i, v in want {
				contains(g[i], v, '${path}[${i}]')!
			}
		}
		else {
			if got.str().to_lower() != want.str().to_lower() {
				return error('${path} is ${got.str()}, not ${want.str()}')
			}
		}
	}
}

fn test_the_otlp_example_is_reproduced() {
	want := json2.decode[json2.Any](os.read_file(os.join_path(@DIR, 'testdata', 'otlp_example_trace.json'))!)!
	got := json2.decode[json2.Any](encode_traces([example_span()], false))!
	contains(got, want, '')!
}

fn full_spans() []trace.ReadOnlySpan {
	res := resource.Resource.new([otel.string_attr('service.name', 'blog'),
		otel.string_attr('service.version', '1.2.0')], 'https://opentelemetry.io/schemas/1.26.0')
	vgraph := trace.InstrumentationScope{
		name:    'five07.vgraph'
		version: '0.1.0'
	}
	app := trace.InstrumentationScope{
		name:       'app'
		schema_url: 'https://opentelemetry.io/schemas/1.26.0'
	}
	tid := '00000000000000000000000000000001'
	remote := otel.SpanContext{
		...sc('4bf92f3577b34da6a3ce929d0e0e4736', '00f067aa0ba902b7')
		state:  otel.TraceState{}.insert('congo', 't61rcWkgMzE') or { panic(err) }
		remote: true
	}
	request := trace.ReadOnlySpan{
		name:         'query Posts'
		span_context: otel.SpanContext{
			...sc(tid, '0000000000000001')
			state: remote.state
		}
		parent:       remote
		kind:         .server
		start_ns:     1700000000000000000
		end_ns:       1700000000005000000
		attributes:   [
			otel.string_attr('graphql.operation.type', 'query'),
			otel.bool_attr('cached', false),
			otel.i64_attr('big', 9_007_199_254_740_993),
			otel.f64_attr('ratio', 0.25),
			otel.f64_attr('nan', math.nan()),
			otel.strings_attr('tags', ['a', 'b']),
			otel.bools_attr('flags', [true]),
			otel.i64s_attr('ids', [i64(1), -2]),
			otel.f64s_attr('ws', [1.5]),
			otel.strings_attr('none', []),
		]
		status:       otel.Status{
			code:        .error
			description: 'timed out'
		}
		scope:        vgraph
		resource:     res
	}
	statement := trace.ReadOnlySpan{
		name:               'SELECT users'
		span_context:       sc(tid, '0000000000000002')
		parent:             sc(tid, '0000000000000001')
		kind:               .client
		start_ns:           1700000000001000000
		end_ns:             1700000000003000000
		dropped_attributes: 2
		events:             [
			trace.Event{
				name:               'exception'
				time_ns:            1700000000002000000
				attributes:         [otel.string_attr('exception.type', 'QueryError')]
				dropped_attributes: 1
			},
		]
		dropped_events:     3
		links:              [
			trace.Link{
				span_context: remote
				attributes:   [otel.int_attr('n', 1)]
			},
		]
		dropped_links:      4
		status:             otel.Status{
			code: .ok
		}
		scope:              vgraph
		resource:           res
	}
	job := trace.ReadOnlySpan{
		name:         'job'
		span_context: sc('00000000000000000000000000000002', '0000000000000003')
		kind:         .consumer
		start_ns:     1700000000000000000
		end_ns:       1700000000000000001
		scope:        app
		resource:     res
	}
	other := trace.ReadOnlySpan{
		name:         'other'
		span_context: sc('00000000000000000000000000000002', '0000000000000004')
		kind:         .producer
		start_ns:     1700000000000000000
		end_ns:       1700000000000000002
		scope:        app
		resource:     resource.Resource.new([otel.string_attr('service.name', 'worker')],
			'')
	}
	return [request, statement, job, other]
}

fn test_the_full_golden_file() {
	got := encode_traces(full_spans(), true) + '\n'
	path := os.join_path(@DIR, 'testdata', 'traces_golden.json')
	if os.getenv('UPDATE_GOLDEN') == '1' {
		os.write_file(path, got)!
	}
	assert got == os.read_file(path)!, 'differs from ${path}; check the change, then run with UPDATE_GOLDEN=1'
}

fn test_the_rules_otlp_json_sets() {
	m := json2.decode[json2.Any](encode_traces(full_spans(), false))!
	groups := (m.as_map()['resourceSpans'] or { panic('none') }).as_array()
	// two resources; the first with two scopes, in first-seen order
	assert groups.len == 2
	first := groups[0].as_map()
	scopes := (first['scopeSpans'] or { panic('') }).as_array()
	assert scopes.len == 2
	assert (first['schemaUrl'] or { '' }).str() == 'https://opentelemetry.io/schemas/1.26.0'
	spans := (scopes[0].as_map()['spans'] or { panic('') }).as_array()
	assert spans.len == 2
	req := spans[0].as_map()
	// 64-bit integers are strings; enums and 32-bit counts are numbers
	assert (req['startTimeUnixNano'] or { 0 }) is string
	assert (req['kind'] or { '' }).int() == 2
	// the remote parent sets both remote bits, over the sampled flag
	assert (req['flags'] or { '' }).int() == 0x301
	assert (req['traceState'] or { '' }).str() == 'congo=t61rcWkgMzE'
	status := (req['status'] or { panic('') }).as_map()
	assert (status['code'] or { '' }).int() == 2
	assert (status['message'] or { '' }).str() == 'timed out'
	stmt := spans[1].as_map()
	assert (stmt['flags'] or { '' }).int() == 0x101
	assert (stmt['droppedEventsCount'] or { '' }).int() == 3
	// an ok status has a code and no message; an unset one is empty
	assert (stmt['status'] or { panic('') }).as_map().len == 1
	job := (scopes[1].as_map()['spans'] or { panic('') }).as_array()[0].as_map()
	assert (job['status'] or { panic('') }).as_map().len == 0
	assert 'parentSpanId' !in job
	assert 'attributes' !in job
}

fn test_an_empty_batch() {
	assert encode_traces([], false) == '{"resourceSpans":[]}'
}

module stdout

import context
import io
import json2
import math
import time
import five07.otel
import five07.otel.sdk.resource
import five07.otel.sdk.trace

// Buffer keeps what is written to it.
@[heap]
struct Buffer {
mut:
	data []u8
}

fn (mut b Buffer) write(buf []u8) !int {
	b.data << buf
	return buf.len
}

fn run(opts Options, work fn (otel.Tracer)) string {
	mut buf := &Buffer{}
	exporter := Exporter.new(Options{
		...opts
		writer: io.Writer(buf)
	})
	provider := trace.TracerProvider.new(
		resource:     resource.Resource.new([otel.string_attr('service.name', 'blog')],
			'')
		sampler:      trace.always_on_sampler()
		id_generator: trace.SequentialIdGenerator.new()
		processors:   [trace.SimpleSpanProcessor.new(exporter)]
		limits:       trace.SpanLimits{}
	) or { panic(err) }
	work(provider.tracer('five07.vgraph', version: '0.1.0'))
	return buf.data.bytestr()
}

const t0 = time.unix(1_700_000_000)

fn at(ms int) time.Time {
	return time.unix_nano(t0.unix_nano() + i64(ms) * 1_000_000)
}

fn request_and_statement(tracer otel.Tracer) {
	ctx, request := tracer.start(context.background(), 'query Posts',
		kind:       .server
		start:      at(0)
		attributes: [otel.string_attr('graphql.operation.type', 'query')]
	)
	_, statement := tracer.start(ctx, 'SELECT users',
		kind:  .client
		start: at(1)
	)
	statement.set_attributes(otel.int_attr('db.rows', 3), otel.strings_attr('tags', [
		'a',
		'b',
	]))
	statement.add_event('retry', timestamp: at(2), attributes: [otel.bool_attr('ok', true)])
	statement.end(end: at(3))
	request.set_status(code: .error, description: 'timed out')
	request.end(end: at(5))
}

fn test_one_line_per_span() {
	out := run(Options{}, request_and_statement)
	lines := out.split_into_lines()
	assert lines.len == 2
	assert lines[0] == '{"name":"SELECT users","trace_id":"00000000000000000000000000000001","span_id":"0000000000000002","parent_span_id":"0000000000000001","kind":"client","start_time":"2023-11-14T22:13:20.001000000Z","end_time":"2023-11-14T22:13:20.003000000Z","duration_ms":2.000,"status":{"code":"unset"},"attributes":{"db.rows":3,"tags":["a","b"]},"events":[{"name":"retry","time":"2023-11-14T22:13:20.002000000Z","attributes":{"ok":true}}],"links":[],"scope":{"name":"five07.vgraph","version":"0.1.0"}}'
	assert lines[1] == '{"name":"query Posts","trace_id":"00000000000000000000000000000001","span_id":"0000000000000001","kind":"server","start_time":"2023-11-14T22:13:20.000000000Z","end_time":"2023-11-14T22:13:20.005000000Z","duration_ms":5.000,"status":{"code":"error","description":"timed out"},"attributes":{"graphql.operation.type":"query"},"events":[],"links":[],"scope":{"name":"five07.vgraph","version":"0.1.0"}}'
	// each line is JSON
	for line in lines {
		_ := json2.decode[json2.Any](line)!
	}
}

fn test_pretty_and_resource() {
	out := run(Options{
		pretty:   true
		resource: true
	}, fn (tracer otel.Tracer) {
		_, span := tracer.start(context.background(), 'a', start: at(0))
		span.end(end: at(1))
	})
	assert out.starts_with('{\n  "name": "a",\n  "trace_id": "00000000000000000000000000000001",\n')
	assert out.contains('\n  "status": {\n    "code": "unset"\n  },\n  "attributes": {},\n  "events": [],\n')
	assert out.contains('\n  "resource": {\n    "service.name": "blog"\n  }\n}\n')
	m := json2.decode[json2.Any](out)!.as_map()
	assert (m['name'] or { '' }).str() == 'a'
}

fn test_values_that_json_lacks() {
	out := run(Options{}, fn (tracer otel.Tracer) {
		_, span := tracer.start(context.background(), 'a\n"b"')
		span.set_attributes(otel.f64_attr('nan', math.nan()), otel.f64_attr('inf', math.inf(1)),
			otel.f64_attr('half', 0.5), otel.string_attr('ctl', 'x\x01y\\'), otel.string_attr('bytes',
				[u8(0x61), 0xff].bytestr()))
		span.end()
	})
	assert out.starts_with('{"name":"a\\n\\"b\\"",')
	assert out.contains('"attributes":{"nan":"NaN","inf":"Infinity","half":0.5,"ctl":"x\\u0001y\\\\","bytes":"a\\u00ff"}')
	_ := json2.decode[json2.Any](out)!
}

fn test_dropped_counts_appear_when_not_zero() {
	mut buf := &Buffer{}
	exporter := Exporter.new(writer: io.Writer(buf))
	provider := trace.TracerProvider.new(
		resource:   resource.Resource.new([], '')
		sampler:    trace.always_on_sampler()
		processors: [trace.SimpleSpanProcessor.new(exporter)]
		limits:     trace.SpanLimits{
			attribute_count: 1
			event_count:     0
		}
	)!
	_, span := provider.tracer('lib').start(context.background(), 'a')
	span.set_attributes(otel.int_attr('a', 1), otel.int_attr('b', 2))
	span.add_event('e')
	span.end()
	out := buf.data.bytestr()
	assert out.contains('"dropped_attributes":1')
	assert out.contains('"dropped_events":1')
	assert !out.contains('dropped_links')
}

fn test_shutdown_stops_it() {
	mut buf := &Buffer{}
	exporter := Exporter.new(writer: io.Writer(buf))
	exporter.shutdown()!
	if _ := exporter.export([trace.ReadOnlySpan{}]) {
		assert false, 'a shut-down exporter wrote'
	}
	assert buf.data.len == 0
}

fn test_it_is_a_span_exporter_and_defaults_to_stdout() {
	e := trace.SpanExporter(Exporter.new())
	e.export([])!
}

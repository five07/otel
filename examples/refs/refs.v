module main

import context
import io
import json2
import os
import five07.otel
import five07.otel.exporters.stdout
import five07.otel.ref
import five07.otel.sdk.resource
import five07.otel.sdk.trace

// ToolCall is one call an agent made: a tool, and its arguments as JSON.
struct ToolCall {
	tool string
	args string
}

// calls is a run of an agent that bills a customer. The arguments hold
// personal data, which must not reach the traces.
const calls = [
	ToolCall{'lookup_customer', '{"email": "alice@example.com"}'},
	ToolCall{'list_invoices', '{"customer_id": "ACCT-0042", "status": "open"}'},
	ToolCall{'send_email', '{"to": "alice@example.com", "subject": "Invoice 42"}'},
	ToolCall{'lookup_customer', '{"email": "bob@example.com"}'},
]

// record runs `calls`, a span for each, and writes the spans to `path` as JSON
// lines. A span carries its arguments' ref, `tool.args_ref`, never the
// arguments.
fn record(path string, refs ref.Refs) ! {
	mut file := os.create(path)!
	defer {
		file.close()
	}
	provider := trace.TracerProvider.new(
		resource:   resource.Resource.new([otel.string_attr('service.name', 'billing-agent')],
			'')
		processors: [trace.SimpleSpanProcessor.new(stdout.Exporter.new(writer: io.Writer(file)))]
	)!
	tracer := provider.tracer('refs-example')
	ctx, run := tracer.start(context.background(), 'agent.run')
	for call in calls {
		args := ref.from_json(json2.decode[json2.Any](call.args)!)!
		_, span := tracer.start(ctx, 'tool.call',
			attributes: [otel.string_attr('gen_ai.tool.name', call.tool)]
		)
		if kv := refs.attribute('tool.args_ref', args) {
			span.set_attributes(kv)
		}
		span.end()
	}
	run.end()
	provider.shutdown()!
}

// Match is a span that touched the value looked for.
struct Match {
	trace_id string
	span_id  string
	tool     string
}

// find makes the ref of `value` again, with the same key, and returns the
// spans in `path` whose `tool.args_ref` is it.
fn find(path string, refs ref.Refs, value string) ![]Match {
	want := refs.ref(ref.from_json(json2.decode[json2.Any](value)!)!)!
	mut out := []Match{}
	for line in os.read_lines(path)! {
		span := json2.decode[json2.Any](line)!.as_map()
		attrs := (span['attributes'] or { continue }).as_map()
		if (attrs['tool.args_ref'] or { continue }).str() == want {
			out << Match{
				trace_id: (span['trace_id'] or { '' }).str()
				span_id:  (span['span_id'] or { '' }).str()
				tool:     (attrs['gen_ai.tool.name'] or { '' }).str()
			}
		}
	}
	return out
}

module main

import os
import five07.otel.ref

const usage = "usage: v -nocache run . record            write traces.jsonl
       v -nocache run . find '<json>'     list the spans whose arguments were <json>"

fn main() {
	// the key comes from OTEL_REF_KEY: set it, or each run makes its own and
	// `find` can't match what `record` wrote
	refs := ref.Refs.new() or {
		eprintln('refs: ${err}')
		exit(1)
	}
	args := os.args[1..]
	if args.len == 1 && args[0] == 'record' {
		record('traces.jsonl', refs) or {
			eprintln('record: ${err}')
			exit(1)
		}
		println('wrote traces.jsonl')
	} else if args.len == 2 && args[0] == 'find' {
		matches := find('traces.jsonl', refs, args[1]) or {
			eprintln('find: ${err}')
			exit(1)
		}
		for m in matches {
			println('${m.tool} in trace ${m.trace_id}, span ${m.span_id}')
		}
		if matches.len == 0 {
			println('no span had those arguments')
		}
	} else {
		eprintln(usage)
		exit(2)
	}
}

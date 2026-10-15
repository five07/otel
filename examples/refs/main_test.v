module main

import os
import five07.otel.ref

fn key() []u8 {
	return []u8{len: 32, init: u8(index)}
}

fn test_a_payload_is_found_again_with_the_key() {
	path := os.join_path(os.vtmp_dir(), 'refs_example_${os.getpid()}.jsonl')
	defer {
		os.rm(path) or {}
	}
	refs := ref.Refs.new(key: key())!
	record(path, refs)!
	// the same arguments in another order or spacing make the same ref
	found := find(path, refs, '{"email":"alice@example.com"}')!
	assert found.len == 1
	assert found[0].tool == 'lookup_customer'
	sent := find(path, refs, '{"subject": "Invoice 42", "to": "alice@example.com"}')!
	assert sent.map(it.tool) == ['send_email']
	assert find(path, refs, '{"email":"carol@example.com"}')!.len == 0
	// every call shares the agent's trace
	bob := find(path, refs, '{"email":"bob@example.com"}')!
	assert bob[0].trace_id == found[0].trace_id
}

fn test_the_traces_hold_no_payload() {
	path := os.join_path(os.vtmp_dir(), 'refs_example_${os.getpid()}_b.jsonl')
	defer {
		os.rm(path) or {}
	}
	record(path, ref.Refs.new(key: key())!)!
	text := os.read_file(path)!
	assert text.count('tool.args_ref') == 4
	for secret in ['alice@example.com', 'bob@example.com', 'ACCT-0042', 'Invoice 42'] {
		assert !text.contains(secret), '${secret} reached the traces'
	}
}

fn test_another_key_finds_nothing() {
	path := os.join_path(os.vtmp_dir(), 'refs_example_${os.getpid()}_c.jsonl')
	defer {
		os.rm(path) or {}
	}
	record(path, ref.Refs.new(key: key())!)!
	mut other := key()
	other[0] = 0xff
	assert find(path, ref.Refs.new(key: other)!, '{"email":"alice@example.com"}')!.len == 0
}

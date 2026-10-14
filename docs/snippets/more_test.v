module main

import os
import five07.otel
import five07.otel.ref

fn test_configured_provider_builds() {
	provider := configured_provider()!
	provider.shutdown()!
	os.unsetenv('OTEL_PROPAGATORS')
	assert propagator().fields() == ['traceparent', 'tracestate', 'baggage']
}

fn test_refs_name_without_revealing() {
	refs := ref.Refs.new(key: []u8{len: 32, init: u8(index)})!
	attrs := tool_span_attributes(refs, 'lookup_customer', '{"email": "alice@example.com"}')!
	assert attrs[1].key == 'tool.args_ref'
	v := attrs[1].value as string
	assert v.starts_with('hmac:') && !v.contains('alice')
	// the same arguments, written another way, give the same ref
	again := tool_span_attributes(refs, 'x', '{ "email":"alice@example.com" }')!
	assert again[1] == attrs[1]
	a := invoice_ref(refs, Invoice{ customer: 'c-1', amount: 5, note: 'x' })!
	b := invoice_ref(refs, Invoice{ customer: 'c-1', amount: 5, note: 'y' })!
	assert a == b
	assert otel.string_attr('k', a).key == 'k'
}

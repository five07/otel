module otel

fn test_trace_id_reads_and_writes_hex() {
	// the example in the W3C Trace Context spec
	id := TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736')!
	assert id.bytes[0] == 0x4b
	assert id.bytes[15] == 0x36
	assert id.hex() == '4bf92f3577b34da6a3ce929d0e0e4736'
	assert '${id}' == '4bf92f3577b34da6a3ce929d0e0e4736'
	assert id.is_valid()
}

fn test_span_id_reads_and_writes_hex() {
	id := SpanId.from_hex('00f067aa0ba902b7')!
	assert id.bytes[0] == 0x00
	assert id.bytes[7] == 0xb7
	assert id.hex() == '00f067aa0ba902b7'
	assert '${id}' == '00f067aa0ba902b7'
	assert id.is_valid()
}

fn test_ids_compare_by_value() {
	a := SpanId.from_hex('00f067aa0ba902b7')!
	b := SpanId.from_hex('00f067aa0ba902b7')!
	c := SpanId.from_hex('00f067aa0ba902b8')!
	assert a == b
	assert a != c
}

fn test_every_byte_round_trips() {
	mut bytes := [16]u8{}
	for i in 0 .. 16 {
		bytes[i] = u8(i * 17)
	}
	id := TraceId{
		bytes: bytes
	}
	assert id.hex() == '00112233445566778899aabbccddeeff'
	assert TraceId.from_hex(id.hex())! == id
}

fn test_zero_ids_are_not_valid() {
	assert !TraceId{}.is_valid()
	assert !SpanId{}.is_valid()
	assert TraceId{}.hex() == '00000000000000000000000000000000'
	if _ := TraceId.from_hex('00000000000000000000000000000000') {
		assert false, 'an all-zero trace id was read'
	} else {
		assert err.msg() == 'a trace id must not be all zero'
	}
	if _ := SpanId.from_hex('0000000000000000') {
		assert false, 'an all-zero span id was read'
	} else {
		assert err.msg() == 'a span id must not be all zero'
	}
}

fn test_bad_hex_is_an_error() {
	bad_trace := {
		'':                                  'a trace id is 32 lowercase hex characters, not 0'
		'4bf92f3577b34da6a3ce929d0e0e473':   'a trace id is 32 lowercase hex characters, not 31'
		'4bf92f3577b34da6a3ce929d0e0e47360': 'a trace id is 32 lowercase hex characters, not 33'
		'4BF92F3577B34DA6A3CE929D0E0E4736':  'a trace id is lowercase hex only'
		'4bf92f3577b34da6a3ce929d0e0e473g':  'a trace id is lowercase hex only'
		'4bf92f3577b34da6-3ce929d0e0e4736':  'a trace id is lowercase hex only'
	}
	for s, want in bad_trace {
		if _ := TraceId.from_hex(s) {
			assert false, '`${s}` was read as a trace id'
		} else {
			assert err.msg() == want
		}
	}
	bad_span := {
		'00f067aa0ba902b':   'a span id is 16 lowercase hex characters, not 15'
		'00F067AA0BA902B7':  'a span id is lowercase hex only'
		'00f067aa 0ba902b7': 'a span id is 16 lowercase hex characters, not 17'
	}
	for s, want in bad_span {
		if _ := SpanId.from_hex(s) {
			assert false, '`${s}` was read as a span id'
		} else {
			assert err.msg() == want
		}
	}
}

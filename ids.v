module otel

const hex_digits = '0123456789abcdef'

// TraceId names a trace: 16 bytes, shared by every span in it. All zero means
// no trace, and is never valid.
pub struct TraceId {
pub:
	bytes [16]u8
}

// TraceId.from_hex reads a trace id written as 32 lowercase hex characters, as
// in a `traceparent` header or OTLP JSON. Upper case is an error, as the W3C
// Trace Context requires, and so is the all-zero id.
pub fn TraceId.from_hex(s string) !TraceId {
	mut id := TraceId{}
	decode_hex(s, mut id.bytes[..], 'trace id')!
	if !id.is_valid() {
		return error('a trace id must not be all zero')
	}
	return id
}

// hex writes the id as 32 lowercase hex characters.
pub fn (id TraceId) hex() string {
	return encode_hex(id.bytes[..])
}

// str is `hex`, so an id prints as it is sent.
pub fn (id TraceId) str() string {
	return id.hex()
}

// is_valid tells whether the id names a trace: any byte not zero.
pub fn (id TraceId) is_valid() bool {
	return !all_zero(id.bytes[..])
}

// SpanId names a span within its trace: 8 bytes. All zero means no span, and is
// never valid.
pub struct SpanId {
pub:
	bytes [8]u8
}

// SpanId.from_hex reads a span id written as 16 lowercase hex characters. Upper
// case is an error, and so is the all-zero id.
pub fn SpanId.from_hex(s string) !SpanId {
	mut id := SpanId{}
	decode_hex(s, mut id.bytes[..], 'span id')!
	if !id.is_valid() {
		return error('a span id must not be all zero')
	}
	return id
}

// hex writes the id as 16 lowercase hex characters.
pub fn (id SpanId) hex() string {
	return encode_hex(id.bytes[..])
}

// str is `hex`, so an id prints as it is sent.
pub fn (id SpanId) str() string {
	return id.hex()
}

// is_valid tells whether the id names a span: any byte not zero.
pub fn (id SpanId) is_valid() bool {
	return !all_zero(id.bytes[..])
}

// decode_hex fills `out` from `s`, two lowercase hex characters a byte. The
// error names what was read, but not the input, which comes from a header.
fn decode_hex(s string, mut out []u8, what string) ! {
	if s.len != out.len * 2 {
		return error('a ${what} is ${out.len * 2} lowercase hex characters, not ${s.len}')
	}
	for i in 0 .. out.len {
		hi := hex_value(s[2 * i]) or { return error('a ${what} is lowercase hex only') }
		lo := hex_value(s[2 * i + 1]) or { return error('a ${what} is lowercase hex only') }
		out[i] = hi << 4 | lo
	}
}

fn hex_value(c u8) ?u8 {
	return match c {
		`0`...`9` { c - `0` }
		`a`...`f` { c - `a` + 10 }
		else { none }
	}
}

fn encode_hex(b []u8) string {
	mut out := []u8{len: b.len * 2}
	for i, x in b {
		out[2 * i] = hex_digits[x >> 4]
		out[2 * i + 1] = hex_digits[x & 0xf]
	}
	return out.bytestr()
}

fn all_zero(b []u8) bool {
	for x in b {
		if x != 0 {
			return false
		}
	}
	return true
}

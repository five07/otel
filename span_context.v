module otel

// TraceFlags are the trace's flags as `traceparent` carries them. Only the
// sampled bit is defined: the caller recorded the trace, and asks the services it
// calls to do the same.
pub struct TraceFlags {
pub:
	bits u8
}

// sampled_flag is the bit of `TraceFlags` that marks a sampled trace.
pub const sampled_flag = u8(0x01)

// is_sampled tells whether the sampled bit is set.
pub fn (f TraceFlags) is_sampled() bool {
	return f.bits & sampled_flag != 0
}

// with_sampled returns the flags with the sampled bit set or cleared, and the
// other bits as they were.
pub fn (f TraceFlags) with_sampled(sampled bool) TraceFlags {
	return TraceFlags{
		bits: if sampled { f.bits | sampled_flag } else { f.bits & ~sampled_flag }
	}
}

// hex writes the flags as two lowercase hex characters, as `traceparent` does.
pub fn (f TraceFlags) hex() string {
	return encode_hex([f.bits])
}

// str is `hex`.
pub fn (f TraceFlags) str() string {
	return f.hex()
}

// SpanContext is what identifies a span to other spans and other services: its
// trace, its own id, the trace's flags and state, and whether it came from
// another process (`remote`, set when it is read from a header).
pub struct SpanContext {
pub:
	trace_id TraceId
	span_id  SpanId
	flags    TraceFlags
	state    TraceState
	remote   bool
}

// is_valid tells whether both ids are valid. A span with an invalid context is
// not part of any trace, and is not propagated.
pub fn (sc SpanContext) is_valid() bool {
	return sc.trace_id.is_valid() && sc.span_id.is_valid()
}

// is_sampled tells whether the trace's sampled flag is set.
pub fn (sc SpanContext) is_sampled() bool {
	return sc.flags.is_sampled()
}

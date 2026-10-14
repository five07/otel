module propagation

import context
import five07.otel

const traceparent_header = 'traceparent'
const tracestate_header = 'tracestate'

// TraceContext propagates the W3C Trace Context headers, `traceparent` and
// `tracestate`.
pub struct TraceContext {}

// inject writes the span context of the span in `ctx`, if it is valid.
pub fn (p TraceContext) inject(ctx context.Context, mut carrier TextMapCarrier) {
	sc := otel.span_from_context(ctx).span_context()
	if !sc.is_valid() {
		return
	}
	carrier.set(traceparent_header, format_traceparent(sc))
	state := sc.state.str()
	if state != '' {
		carrier.set(tracestate_header, state)
	}
}

// extract returns `ctx` with the remote span context the headers describe, so
// spans started from it continue the caller's trace. A malformed `traceparent`
// leaves `ctx` as it is; a malformed `tracestate` is dropped alone.
pub fn (p TraceContext) extract(ctx context.Context, carrier TextMapCarrier) context.Context {
	header := carrier.get(traceparent_header) or { return ctx }
	sc := parse_traceparent(header) or { return ctx }
	state := otel.TraceState.parse(carrier.get(tracestate_header) or { '' }) or {
		otel.TraceState{}
	}
	return otel.context_with_span_context(ctx, otel.SpanContext{
		...sc
		state: state
	})
}

// fields are `traceparent` and `tracestate`.
pub fn (p TraceContext) fields() []string {
	return [traceparent_header, tracestate_header]
}

// format_traceparent writes version `00`, the ids, and the sampled flag only.
fn format_traceparent(sc otel.SpanContext) string {
	flags := otel.TraceFlags{}.with_sampled(sc.is_sampled())
	return '00-${sc.trace_id.hex()}-${sc.span_id.hex()}-${flags.hex()}'
}

// parse_traceparent reads `version-traceid-spanid-flags`, as the W3C Trace
// Context specifies: lowercase hex, ids not all zero, version `ff` invalid,
// version `00` exactly 55 characters, a later version maybe longer with its
// extra fields after a `-`. Spaces and tabs around it are dropped. Only the
// sampled flag is kept, as the Go SDK does.
fn parse_traceparent(header string) !otel.SpanContext {
	h := header.trim(' \t')
	if h.len < 55 || h[2] != `-` || h[35] != `-` || h[52] != `-` {
		return error('a traceparent is `version-traceid-spanid-flags`')
	}
	version := parse_hex_byte(h[0..2])!
	if version == 0xff {
		return error('traceparent version ff is invalid')
	}
	if version == 0 && h.len != 55 {
		return error('a version 00 traceparent is 55 characters')
	}
	if h.len > 55 && h[55] != `-` {
		return error('a traceparent field ends at a `-`')
	}
	trace_id := otel.TraceId.from_hex(h[3..35])!
	span_id := otel.SpanId.from_hex(h[36..52])!
	flags := parse_hex_byte(h[53..55])!
	return otel.SpanContext{
		trace_id: trace_id
		span_id:  span_id
		flags:    otel.TraceFlags{}.with_sampled(flags & otel.sampled_flag != 0)
		remote:   true
	}
}

fn parse_hex_byte(s string) !u8 {
	mut v := u8(0)
	for c in s {
		v = v << 4 | match c {
			`0`...`9` { c - `0` }
			`a`...`f` { c - `a` + 10 }
			else { return error('a traceparent is lowercase hex') }
		}
	}
	return v
}

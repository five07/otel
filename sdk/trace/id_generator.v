module trace

import crypto.rand as crypto_rand
import encoding.binary
import rand.xoroshiro128pp
import five07.otel

// IdGenerator makes the ids of new traces and spans. Its methods may be called
// from any thread, and never return an all-zero id.
pub interface IdGenerator {
	// new_trace_id returns the id of a new trace
	new_trace_id() otel.TraceId
	// new_span_id returns the id of a new span
	new_span_id() otel.SpanId
}

// RandomIdGenerator makes random ids from a fast generator, seeded once from
// the operating system's secure source, so making an id is no system call.
// The ids are unpredictable enough to keep traces apart, not to keep secrets.
@[heap]
pub struct RandomIdGenerator {
mut:
	rng shared xoroshiro128pp.XOROS128PPRNG
}

// RandomIdGenerator.new returns a generator seeded from `crypto.rand`.
pub fn RandomIdGenerator.new() !&RandomIdGenerator {
	seed := crypto_rand.bytes(4 * xoroshiro128pp.seed_len)!
	words := []u32{len: xoroshiro128pp.seed_len, init: binary.little_endian_u32_at(seed, 4 * index)}
	return RandomIdGenerator.with_seed(words)
}

// RandomIdGenerator.with_seed returns a generator that makes the same ids for
// the same seed, for tests; `seed` is four u32s.
pub fn RandomIdGenerator.with_seed(seed []u32) &RandomIdGenerator {
	mut rng := xoroshiro128pp.XOROS128PPRNG{}
	rng.seed(seed)
	return &RandomIdGenerator{
		rng: rng
	}
}

// new_trace_id returns 16 random bytes, not all zero.
pub fn (g &RandomIdGenerator) new_trace_id() otel.TraceId {
	for {
		hi, lo := lock g.rng {
			g.rng.u64(), g.rng.u64()
		}
		id := otel.TraceId{
			bytes: trace_id_bytes(hi, lo)
		}
		if id.is_valid() {
			return id
		}
	}
	return otel.TraceId{}
}

// new_span_id returns 8 random bytes, not all zero.
pub fn (g &RandomIdGenerator) new_span_id() otel.SpanId {
	for {
		n := lock g.rng {
			g.rng.u64()
		}
		if n != 0 {
			return otel.SpanId{
				bytes: span_id_bytes(n)
			}
		}
	}
	return otel.SpanId{}
}

// SequentialIdGenerator makes the ids 1, 2, 3 and on, trace and span ids each
// counting on their own, so a test can know the ids its spans will get.
@[heap]
pub struct SequentialIdGenerator {
mut:
	counts shared Counts
}

struct Counts {
mut:
	trace u64
	span  u64
}

// SequentialIdGenerator.new returns a generator whose first ids are 1.
pub fn SequentialIdGenerator.new() &SequentialIdGenerator {
	return &SequentialIdGenerator{}
}

// new_trace_id returns the next trace id: `000…01`, then `000…02`.
pub fn (g &SequentialIdGenerator) new_trace_id() otel.TraceId {
	n := lock g.counts {
		g.counts.trace++
		g.counts.trace
	}
	return otel.TraceId{
		bytes: trace_id_bytes(0, n)
	}
}

// new_span_id returns the next span id: `000…01`, then `000…02`.
pub fn (g &SequentialIdGenerator) new_span_id() otel.SpanId {
	n := lock g.counts {
		g.counts.span++
		g.counts.span
	}
	return otel.SpanId{
		bytes: span_id_bytes(n)
	}
}

// trace_id_bytes writes `hi` then `lo`, big-endian.
fn trace_id_bytes(hi u64, lo u64) [16]u8 {
	mut b := [16]u8{}
	for i in 0 .. 8 {
		b[i] = u8(hi >> (56 - 8 * i))
		b[8 + i] = u8(lo >> (56 - 8 * i))
	}
	return b
}

// span_id_bytes writes `n` big-endian.
fn span_id_bytes(n u64) [8]u8 {
	mut b := [8]u8{}
	for i in 0 .. 8 {
		b[i] = u8(n >> (56 - 8 * i))
	}
	return b
}

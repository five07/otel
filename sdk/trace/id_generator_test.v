module trace

import five07.otel

fn test_random_ids_are_valid_and_differ() {
	g := RandomIdGenerator.new()!
	mut traces := map[string]bool{}
	mut spans := map[string]bool{}
	for _ in 0 .. 1000 {
		t := g.new_trace_id()
		s := g.new_span_id()
		assert t.is_valid()
		assert s.is_valid()
		traces[t.hex()] = true
		spans[s.hex()] = true
	}
	assert traces.len == 1000
	assert spans.len == 1000
}

fn test_two_generators_make_different_ids() {
	a := RandomIdGenerator.new()!
	b := RandomIdGenerator.new()!
	assert a.new_trace_id() != b.new_trace_id()
}

fn test_a_seed_gives_the_same_ids() {
	a := RandomIdGenerator.with_seed([u32(1), 2, 3, 4])
	b := RandomIdGenerator.with_seed([u32(1), 2, 3, 4])
	c := RandomIdGenerator.with_seed([u32(1), 2, 3, 5])
	ta := a.new_trace_id()
	assert ta == b.new_trace_id()
	assert ta != c.new_trace_id()
	assert a.new_span_id() == b.new_span_id()
}

fn test_random_ids_are_safe_across_threads() {
	g := RandomIdGenerator.new()!
	mut threads := []thread []string{}
	for _ in 0 .. 8 {
		threads << spawn fn (g IdGenerator) []string {
			mut ids := []string{}
			for _ in 0 .. 2000 {
				ids << g.new_span_id().hex()
			}
			return ids
		}(g)
	}
	mut seen := map[string]bool{}
	for ids in threads.wait() {
		for id in ids {
			seen[id] = true
		}
	}
	assert seen.len == 16_000
}

fn test_sequential_ids_count_from_one() {
	g := SequentialIdGenerator.new()
	assert g.new_trace_id().hex() == '00000000000000000000000000000001'
	assert g.new_trace_id().hex() == '00000000000000000000000000000002'
	assert g.new_span_id().hex() == '0000000000000001'
	assert g.new_span_id().hex() == '0000000000000002'
	assert g.new_trace_id().hex() == '00000000000000000000000000000003'
}

fn test_byte_order_is_big_endian() {
	assert otel.TraceId{
		bytes: trace_id_bytes(0x0102030405060708, 0x090a0b0c0d0e0f10)
	}.hex() == '0102030405060708090a0b0c0d0e0f10'
	assert otel.SpanId{
		bytes: span_id_bytes(0xa1b2c3d4e5f60718)
	}.hex() == 'a1b2c3d4e5f60718'
}

fn test_generators_are_id_generators() {
	gens := [IdGenerator(RandomIdGenerator.new()!), IdGenerator(SequentialIdGenerator.new())]
	for g in gens {
		assert g.new_trace_id().is_valid()
		assert g.new_span_id().is_valid()
	}
}

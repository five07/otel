module trace

import context
import os
import five07.otel

fn params(trace_hex string, parent otel.SpanContext) SamplingParameters {
	return SamplingParameters{
		parent:   parent
		trace_id: otel.TraceId.from_hex(trace_hex) or { panic(err) }
		name:     'span'
	}
}

fn parent(sampled bool, remote bool) otel.SpanContext {
	return otel.SpanContext{
		trace_id: otel.TraceId.from_hex('4bf92f3577b34da6a3ce929d0e0e4736') or { panic(err) }
		span_id:  otel.SpanId.from_hex('00f067aa0ba902b7') or { panic(err) }
		flags:    otel.TraceFlags{}.with_sampled(sampled)
		state:    otel.TraceState{}.insert('congo', 't61rcWkgMzE') or { panic(err) }
		remote:   remote
	}
}

const any_trace = '4bf92f3577b34da6a3ce929d0e0e4736'

fn test_always_on_and_off() {
	on := always_on_sampler().should_sample(params(any_trace, parent(false, true)))
	assert on.decision == .record_and_sample
	assert on.trace_state.get('congo')? == 't61rcWkgMzE'
	off := always_off_sampler().should_sample(params(any_trace, parent(true, true)))
	assert off.decision == .drop
	assert off.trace_state.get('congo')? == 't61rcWkgMzE'
}

fn test_ratio_reads_the_last_8_bytes_of_the_trace_id() {
	half := trace_id_ratio_based(0.5)
	// the last 8 bytes, shifted right by one, against 0.5 × 2⁶³ = 2⁶²
	assert half.should_sample(params('ffffffffffffffff0000000000000001', otel.SpanContext{})).decision == .record_and_sample
	assert half.should_sample(params('ffffffffffffffff7ffffffffffffffe', otel.SpanContext{})).decision == .record_and_sample
	assert half.should_sample(params('ffffffffffffffff8000000000000000', otel.SpanContext{})).decision == .drop
	assert half.should_sample(params('0000000000000000ffffffffffffffff', otel.SpanContext{})).decision == .drop
	// the first 8 bytes don't count
	assert half.should_sample(params('00000000000000017ffffffffffffffe', otel.SpanContext{})).decision == .record_and_sample
}

fn test_ratio_ends() {
	all := trace_id_ratio_based(1)
	none_ := trace_id_ratio_based(0)
	above := trace_id_ratio_based(2)
	below := trace_id_ratio_based(-1)
	for hex in ['0000000000000000ffffffffffffffff', '00000000000000000000000000000001', any_trace] {
		assert all.should_sample(params(hex, otel.SpanContext{})).decision == .record_and_sample
		assert above.should_sample(params(hex, otel.SpanContext{})).decision == .record_and_sample
		assert none_.should_sample(params(hex, otel.SpanContext{})).decision == .drop
		assert below.should_sample(params(hex, otel.SpanContext{})).decision == .drop
	}
}

fn test_ratio_keeps_about_its_share_and_more_with_a_higher_ratio() {
	ids := RandomIdGenerator.with_seed([u32(7), 7, 7, 7])
	quarter := trace_id_ratio_based(0.25)
	half := trace_id_ratio_based(0.5)
	mut kept_quarter := 0
	mut kept_half := 0
	for _ in 0 .. 20_000 {
		p := SamplingParameters{
			trace_id: ids.new_trace_id()
		}
		q := quarter.should_sample(p).decision == .record_and_sample
		h := half.should_sample(p).decision == .record_and_sample
		if q {
			kept_quarter++
			// a trace kept at 0.25 is kept at 0.5 too
			assert h
		}
		if h {
			kept_half++
		}
	}
	assert kept_quarter > 4_500 && kept_quarter < 5_500
	assert kept_half > 9_500 && kept_half < 10_500
}

fn test_parent_based_follows_the_parent() {
	s := parent_based(always_off_sampler())
	// no parent: the root sampler
	assert s.should_sample(params(any_trace, otel.SpanContext{})).decision == .drop
	assert s.should_sample(params(any_trace, parent(true, true))).decision == .record_and_sample
	assert s.should_sample(params(any_trace, parent(false, true))).decision == .drop
	assert s.should_sample(params(any_trace, parent(true, false))).decision == .record_and_sample
	assert s.should_sample(params(any_trace, parent(false, false))).decision == .drop
}

fn test_parent_based_delegates_can_be_set() {
	s := parent_based(always_on_sampler(),
		remote_parent_sampled:     always_off_sampler()
		remote_parent_not_sampled: always_on_sampler()
		local_parent_sampled:      always_off_sampler()
		local_parent_not_sampled:  always_on_sampler()
	)
	assert s.should_sample(params(any_trace, otel.SpanContext{})).decision == .record_and_sample
	assert s.should_sample(params(any_trace, parent(true, true))).decision == .drop
	assert s.should_sample(params(any_trace, parent(false, true))).decision == .record_and_sample
	assert s.should_sample(params(any_trace, parent(true, false))).decision == .drop
	assert s.should_sample(params(any_trace, parent(false, false))).decision == .record_and_sample
}

fn test_descriptions() {
	assert always_on_sampler().description() == 'AlwaysOnSampler'
	assert always_off_sampler().description() == 'AlwaysOffSampler'
	assert trace_id_ratio_based(0.25).description() == 'TraceIDRatioBased{0.25}'
	assert trace_id_ratio_based(1).description() == 'AlwaysOnSampler'
	assert trace_id_ratio_based(0).description() == 'TraceIDRatioBased{0}'
	assert trace_id_ratio_based(-1).description() == 'TraceIDRatioBased{0}'
	assert parent_based(trace_id_ratio_based(0.5)).description() == 'ParentBased{root:TraceIDRatioBased{0.5},remoteParentSampled:AlwaysOnSampler,remoteParentNotSampled:AlwaysOffSampler,localParentSampled:AlwaysOnSampler,localParentNotSampled:AlwaysOffSampler}'
}

fn sampler_description() (string, []string) {
	s, warnings := sampler_from_env()
	return s.description(), warnings
}

fn test_sampler_from_the_environment() {
	os.unsetenv('OTEL_TRACES_SAMPLER')
	os.unsetenv('OTEL_TRACES_SAMPLER_ARG')
	default_desc := parent_based(always_on_sampler()).description()
	d, w := sampler_description()
	assert d == default_desc
	assert w.len == 0
	for name, want in {
		'always_on':                'AlwaysOnSampler'
		'ALWAYS_OFF':               'AlwaysOffSampler'
		'traceidratio':             'AlwaysOnSampler'
		'parentbased_always_off':   parent_based(always_off_sampler()).description()
		'parentbased_traceidratio': parent_based(trace_id_ratio_based(1)).description()
	} {
		os.setenv('OTEL_TRACES_SAMPLER', name, true)
		got, _ := sampler_description()
		assert got == want
	}
	os.setenv('OTEL_TRACES_SAMPLER', 'traceidratio', true)
	os.setenv('OTEL_TRACES_SAMPLER_ARG', ' 0.1 ', true)
	tenth, _ := sampler_description()
	assert tenth == 'TraceIDRatioBased{0.1}'
	// a bad ratio is 1, with a warning
	for arg, want in {
		'half': 'OTEL_TRACES_SAMPLER_ARG: `half` is not a number; using 1'
		'1.5':  'OTEL_TRACES_SAMPLER_ARG: `1.5` is not from 0 to 1; using 1'
		'-0.1': 'OTEL_TRACES_SAMPLER_ARG: `-0.1` is not from 0 to 1; using 1'
	} {
		os.setenv('OTEL_TRACES_SAMPLER_ARG', arg, true)
		got, warnings := sampler_description()
		assert got == 'AlwaysOnSampler'
		assert warnings == [want]
	}
	// an unknown sampler is the default, with a warning, and the provider builds
	os.unsetenv('OTEL_TRACES_SAMPLER_ARG')
	os.setenv('OTEL_TRACES_SAMPLER', 'jaeger_remote', true)
	got, warnings := sampler_description()
	assert got == default_desc
	assert warnings == ['OTEL_TRACES_SAMPLER: `jaeger_remote` is not a sampler this SDK has; using parentbased_always_on']
	_ := TracerProvider.new()!
	os.unsetenv('OTEL_TRACES_SAMPLER')
}

fn test_the_default_provider_drops_the_children_of_an_unsampled_parent() {
	os.unsetenv('OTEL_TRACES_SAMPLER')
	os.unsetenv('OTEL_TRACES_SAMPLER_ARG')
	os.unsetenv('OTEL_RESOURCE_ATTRIBUTES')
	p := TracerProvider.new()!
	assert p.sampler.description().starts_with('ParentBased{root:AlwaysOnSampler,')
	ctx := otel.context_with_span_context(context.background(), parent(false, true))
	_, span := p.tracer('lib').start(ctx, 'child')
	assert !span.is_recording()
	assert span.span_context().trace_id == parent(false, true).trace_id
	_, root := p.tracer('lib').start(context.background(), 'root')
	assert root.is_recording()
}

fn test_parent_based_tells_remote_parents_from_local_ones() {
	s := parent_based(always_on_sampler(), remote_parent_sampled: always_off_sampler())
	assert s.should_sample(params(any_trace, parent(true, true))).decision == .drop
	assert s.should_sample(params(any_trace, parent(true, false))).decision == .record_and_sample
}

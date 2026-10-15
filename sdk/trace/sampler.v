module trace

import os
import strconv
import five07.otel

// SamplingDecision is whether a new span is kept: not at all, recorded but not
// exported, or recorded, exported, and marked sampled for the services it calls.
pub enum SamplingDecision {
	drop
	record_only
	record_and_sample
}

// SamplingParameters are what a sampler knows about a span at its start.
pub struct SamplingParameters {
pub:
	// parent is the parent's span context, invalid for a root span
	parent     otel.SpanContext
	trace_id   otel.TraceId
	name       string
	kind       otel.SpanKind
	attributes []otel.KeyValue
	links      []otel.Link
}

// SamplingResult is a sampler's decision, with attributes it adds to the span
// and the trace state the span carries on.
pub struct SamplingResult {
pub:
	decision    SamplingDecision
	attributes  []otel.KeyValue
	trace_state otel.TraceState
}

// Sampler decides which spans are kept. It is asked once per span, at its start,
// from any thread.
pub interface Sampler {
	should_sample(p SamplingParameters) SamplingResult
	// description names the sampler and its settings, such as
	// `TraceIDRatioBased{0.25}`
	description() string
}

// always_on_sampler keeps every span.
pub fn always_on_sampler() Sampler {
	return AlwaysOnSampler{}
}

// always_off_sampler keeps no span.
pub fn always_off_sampler() Sampler {
	return AlwaysOffSampler{}
}

// trace_id_ratio_based keeps the share `ratio` (from 0 to 1) of traces, decided
// from the trace id alone, so every service that uses the same ratio keeps the
// same traces. Below 0 keeps none; 1 or more is `always_on_sampler()`, as in
// the Go SDK.
pub fn trace_id_ratio_based(ratio f64) Sampler {
	if ratio >= 1 {
		return AlwaysOnSampler{}
	}
	r := if ratio > 0 { ratio } else { 0.0 }
	return TraceIdRatioBasedSampler{
		ratio: r
		bound: u64(r * f64(u64(1) << 63))
	}
}

// ParentBasedOptions are the samplers `parent_based` asks for a span that has
// a parent, by where the parent is and whether it was sampled. By default a
// sampled parent's children are kept, and an unsampled one's dropped.
@[params]
pub struct ParentBasedOptions {
pub:
	remote_parent_sampled     ?Sampler
	remote_parent_not_sampled ?Sampler
	local_parent_sampled      ?Sampler
	local_parent_not_sampled  ?Sampler
}

// parent_based follows the parent's decision, so a trace is kept or dropped
// whole, and asks `root` for a span with no parent. It is the default sampler,
// over `always_on_sampler()`.
pub fn parent_based(root Sampler, opts ParentBasedOptions) Sampler {
	return ParentBasedSampler{
		root:                      root
		remote_parent_sampled:     opts.remote_parent_sampled or { AlwaysOnSampler{} }
		remote_parent_not_sampled: opts.remote_parent_not_sampled or { AlwaysOffSampler{} }
		local_parent_sampled:      opts.local_parent_sampled or { AlwaysOnSampler{} }
		local_parent_not_sampled:  opts.local_parent_not_sampled or { AlwaysOffSampler{} }
	}
}

// AlwaysOnSampler keeps every span.
pub struct AlwaysOnSampler {}

// should_sample records and samples, keeping the parent's trace state.
pub fn (s AlwaysOnSampler) should_sample(p SamplingParameters) SamplingResult {
	return SamplingResult{
		decision:    .record_and_sample
		trace_state: p.parent.state
	}
}

// description is `AlwaysOnSampler`.
pub fn (s AlwaysOnSampler) description() string {
	return 'AlwaysOnSampler'
}

// AlwaysOffSampler keeps no span.
pub struct AlwaysOffSampler {}

// should_sample drops, keeping the parent's trace state for the services the
// trace goes on to.
pub fn (s AlwaysOffSampler) should_sample(p SamplingParameters) SamplingResult {
	return SamplingResult{
		decision:    .drop
		trace_state: p.parent.state
	}
}

// description is `AlwaysOffSampler`.
pub fn (s AlwaysOffSampler) description() string {
	return 'AlwaysOffSampler'
}

// TraceIdRatioBasedSampler keeps a share of traces; see `trace_id_ratio_based`.
pub struct TraceIdRatioBasedSampler {
	ratio f64
	bound u64
}

// should_sample keeps the trace when its id's last 8 bytes, shifted right by
// one, are below `ratio` × 2⁶³: the same test as the Go SDK, so services in
// both languages keep the same traces.
pub fn (s TraceIdRatioBasedSampler) should_sample(p SamplingParameters) SamplingResult {
	mut x := u64(0)
	for b in p.trace_id.bytes[8..] {
		x = x << 8 | b
	}
	return SamplingResult{
		decision:    if x >> 1 < s.bound { .record_and_sample } else { .drop }
		trace_state: p.parent.state
	}
}

// description is `TraceIDRatioBased{<ratio>}`, as in the Go SDK.
pub fn (s TraceIdRatioBasedSampler) description() string {
	return 'TraceIDRatioBased{${format_ratio(s.ratio)}}'
}

// ParentBasedSampler follows a span's parent; see `parent_based`.
pub struct ParentBasedSampler {
	root                      Sampler
	remote_parent_sampled     Sampler
	remote_parent_not_sampled Sampler
	local_parent_sampled      Sampler
	local_parent_not_sampled  Sampler
}

// should_sample asks the sampler for the span's kind of parent, or `root`.
pub fn (s ParentBasedSampler) should_sample(p SamplingParameters) SamplingResult {
	parent := p.parent
	delegate := if !parent.is_valid() {
		s.root
	} else if parent.remote {
		if parent.is_sampled() { s.remote_parent_sampled } else { s.remote_parent_not_sampled }
	} else {
		if parent.is_sampled() { s.local_parent_sampled } else { s.local_parent_not_sampled }
	}
	return delegate.should_sample(p)
}

// description names the five samplers, as the Go SDK does.
pub fn (s ParentBasedSampler) description() string {
	return 'ParentBased{root:${s.root.description()},remoteParentSampled:${s.remote_parent_sampled.description()},remoteParentNotSampled:${s.remote_parent_not_sampled.description()},localParentSampled:${s.local_parent_sampled.description()},localParentNotSampled:${s.local_parent_not_sampled.description()}}'
}

// sampler_from_env returns the sampler `OTEL_TRACES_SAMPLER` names, with
// `OTEL_TRACES_SAMPLER_ARG` as the ratio of the ratio samplers (1 if unset):
// `always_on`, `always_off`, `traceidratio`, and `parentbased_` before each of
// them. Unset, it is `parentbased_always_on`. Another name falls back to that
// default, and a ratio that isn't a number from 0 to 1 to 1, each with a
// warning, as the specification asks.
fn sampler_from_env() (Sampler, []string) {
	mut warnings := []string{}
	name := os.getenv('OTEL_TRACES_SAMPLER').trim_space().to_lower()
	arg := os.getenv('OTEL_TRACES_SAMPLER_ARG').trim_space()
	mut ratio := 1.0
	if arg != '' {
		if r := strconv.atof64(arg) {
			if r >= 0 && r <= 1 {
				ratio = r
			} else {
				warnings << 'OTEL_TRACES_SAMPLER_ARG: `${arg}` is not from 0 to 1; using 1'
			}
		} else {
			warnings << 'OTEL_TRACES_SAMPLER_ARG: `${arg}` is not a number; using 1'
		}
	}
	sampler := match name {
		'', 'parentbased_always_on' {
			parent_based(always_on_sampler())
		}
		'always_on' {
			always_on_sampler()
		}
		'always_off' {
			always_off_sampler()
		}
		'traceidratio' {
			trace_id_ratio_based(ratio)
		}
		'parentbased_always_off' {
			parent_based(always_off_sampler())
		}
		'parentbased_traceidratio' {
			parent_based(trace_id_ratio_based(ratio))
		}
		else {
			warnings << 'OTEL_TRACES_SAMPLER: `${name}` is not a sampler this SDK has; using parentbased_always_on'
			parent_based(always_on_sampler())
		}
	}
	return sampler, warnings
}

// format_ratio writes a whole number without a fraction (`1`, not `1.0`), as
// Go's `%g` does.
fn format_ratio(r f64) string {
	return if r == f64(i64(r)) { i64(r).str() } else { '${r:g}' }
}

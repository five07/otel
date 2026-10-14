module propagation

import context
import os

// Composite runs several propagators: each injects in turn, and each extracts
// from the context the one before returned.
pub struct Composite {
	propagators []TextMapPropagator
}

// composite returns a propagator that runs `propagators` in order.
pub fn composite(propagators ...TextMapPropagator) TextMapPropagator {
	return Composite{
		propagators: propagators
	}
}

// inject has each propagator inject.
pub fn (c Composite) inject(ctx context.Context, mut carrier TextMapCarrier) {
	for p in c.propagators {
		p.inject(ctx, mut carrier)
	}
}

// extract has each propagator extract, in turn.
pub fn (c Composite) extract(ctx context.Context, carrier TextMapCarrier) context.Context {
	mut out := ctx
	for p in c.propagators {
		out = p.extract(out, carrier)
	}
	return out
}

// fields are every propagator's fields, each once.
pub fn (c Composite) fields() []string {
	mut out := []string{}
	for p in c.propagators {
		for f in p.fields() {
			if f !in out {
				out << f
			}
		}
	}
	return out
}

// default_propagator returns W3C Trace Context and Baggage, the specification's
// default.
pub fn default_propagator() TextMapPropagator {
	return composite(TraceContext{}, BaggagePropagator{})
}

// from_env returns the propagators `OTEL_PROPAGATORS` names, comma-separated:
// `tracecontext`, `baggage`, or `none` for none at all. Unset, it is
// `tracecontext,baggage`. A name this SDK doesn't have (`b3`, `jaeger`) is
// skipped with a warning on stderr, as the specification asks.
pub fn from_env() TextMapPropagator {
	value := os.getenv('OTEL_PROPAGATORS').trim_space()
	if value == '' {
		return default_propagator()
	}
	mut propagators := []TextMapPropagator{}
	for raw in value.split(',') {
		name := raw.trim_space().to_lower()
		match name {
			'tracecontext' { propagators << TraceContext{} }
			'baggage' { propagators << BaggagePropagator{} }
			'none' { return composite() }
			'' {}
			else {
				eprintln('otel: OTEL_PROPAGATORS: `${name}` is not a propagator this SDK has; skipped')
			}
		}
	}
	return composite(...propagators)
}

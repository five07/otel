// Package propagation carries trace context and baggage across process
// boundaries, in the W3C `traceparent`, `tracestate` and `baggage` headers.
module propagation

import context

// TextMapCarrier is where a propagator reads and writes its headers: an HTTP
// request's headers, a message's attributes.
pub interface TextMapCarrier {
	// get returns the value of `key`, or none
	get(key string) ?string
	// keys returns every key the carrier holds
	keys() []string
	// set sets `key` to `value`, replacing any value it had
mut:
	set(key string, value string)
}

// TextMapPropagator moves what a context carries in and out of a carrier: an
// app extracts it from an incoming request, and injects it into an outgoing
// one.
pub interface TextMapPropagator {
	// inject writes what `ctx` carries into `carrier`
	inject(ctx context.Context, mut carrier TextMapCarrier)
	// extract returns `ctx` with what `carrier` holds; what is missing or
	// malformed is left out
	extract(ctx context.Context, carrier TextMapCarrier) context.Context
	// fields are the keys the propagator reads and writes
	fields() []string
}

// MapCarrier holds headers in a map. Keys are lowercased, as HTTP header names
// are case-insensitive.
pub struct MapCarrier {
mut:
	values map[string]string
}

// MapCarrier.new returns a carrier holding `headers`, such as an incoming
// request's.
pub fn MapCarrier.new(headers map[string]string) MapCarrier {
	mut values := map[string]string{}
	for k, v in headers {
		values[k.to_lower()] = v
	}
	return MapCarrier{
		values: values
	}
}

// get returns the value of `key`, in any case.
pub fn (c MapCarrier) get(key string) ?string {
	return c.values[key.to_lower()] or { return none }
}

// keys returns the keys, lowercased.
pub fn (c MapCarrier) keys() []string {
	return c.values.keys()
}

// set sets `key`, lowercased, to `value`.
pub fn (mut c MapCarrier) set(key string, value string) {
	c.values[key.to_lower()] = value
}

// to_map returns the headers, to add to an outgoing request.
pub fn (c MapCarrier) to_map() map[string]string {
	return c.values.clone()
}

// GetterCarrier reads headers through a function, for a framework whose
// request has its own header type: `GetterCarrier{get_fn: fn [req] (k string)
// ?string { ... }}`. It can only be extracted from.
pub struct GetterCarrier {
pub:
	get_fn fn (key string) ?string @[required]
}

// get calls `get_fn`.
pub fn (c GetterCarrier) get(key string) ?string {
	return c.get_fn(key)
}

// keys is empty: a getter can't list them.
pub fn (c GetterCarrier) keys() []string {
	return []
}

// set does nothing: a getter can't be written.
pub fn (mut c GetterCarrier) set(key string, value string) {}

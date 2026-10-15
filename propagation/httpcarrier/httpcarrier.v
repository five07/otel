// Package httpcarrier carries trace context in `net.http` headers, the type
// `net.http`, veb and vweb hand a request's headers over as. It is apart from
// `propagation` so that only the programs that use it compile `net.http`.
module httpcarrier

import net.http

// HeaderCarrier reads and writes a propagator's headers in an `http.Header`.
// Names are case-insensitive, as in HTTP.
pub struct HeaderCarrier {
pub mut:
	header http.Header
}

// new returns a carrier over `header`: an incoming request's, to extract from,
// or a new one, to inject into and then send.
pub fn new(header http.Header) HeaderCarrier {
	return HeaderCarrier{
		header: header
	}
}

// get returns the first value of `key`, in any case, or none.
pub fn (c HeaderCarrier) get(key string) ?string {
	return c.header.get_custom(key)
}

// keys returns the header names.
pub fn (c HeaderCarrier) keys() []string {
	return c.header.keys()
}

// set sets `key` to `value`, replacing its values. A name or value HTTP doesn't
// allow is left out, as a propagator leaves out what is malformed.
pub fn (mut c HeaderCarrier) set(key string, value string) {
	c.header.set_custom(key, value) or {}
}

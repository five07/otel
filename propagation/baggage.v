module propagation

import context
import five07.otel

const baggage_header = 'baggage'

// BaggagePropagator propagates the W3C `baggage` header.
pub struct BaggagePropagator {}

// inject writes the baggage `ctx` carries, if any.
pub fn (p BaggagePropagator) inject(ctx context.Context, mut carrier TextMapCarrier) {
	header := otel.baggage_from_context(ctx).str()
	if header != '' {
		carrier.set(baggage_header, header)
	}
}

// extract returns `ctx` with the baggage the header holds. A malformed header
// is dropped whole, leaving `ctx` as it is.
pub fn (p BaggagePropagator) extract(ctx context.Context, carrier TextMapCarrier) context.Context {
	header := carrier.get(baggage_header) or { return ctx }
	b := otel.Baggage.parse(header) or { return ctx }
	if b.len() == 0 {
		return ctx
	}
	return otel.context_with_baggage(ctx, b)
}

// fields is `baggage`.
pub fn (p BaggagePropagator) fields() []string {
	return [baggage_header]
}

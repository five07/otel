module otel

import context

// span_key_cell exists for its address, which is the context key of the current
// span: no other package can make the same key. Each key's cell holds its own
// value, so a compiler can't merge two cells into one address.
const span_key_cell = u8(1)

fn span_key() context.Key {
	return voidptr(&span_key_cell)
}

// context_with_span returns `ctx` with `span` as its current span: the parent
// of the spans started from it.
pub fn context_with_span(ctx context.Context, span Span) context.Context {
	return context.with_value(ctx, span_key(), span)
}

// span_from_context returns the current span of `ctx`. With none, it returns a
// `NoopSpan`, so a caller can always use the result.
pub fn span_from_context(ctx context.Context) Span {
	if value := ctx.value(span_key()) {
		if value is Span {
			return value
		}
	}
	return NoopSpan{}
}

// context_with_span_context returns `ctx` with a span that records nothing and
// carries `sc`, such as one read from a request's `traceparent`: spans started
// from it are its children, in the caller's trace.
pub fn context_with_span_context(ctx context.Context, sc SpanContext) context.Context {
	return context_with_span(ctx, NoopSpan{
		context: sc
	})
}

// baggage_key_cell exists for its address, the context key of the baggage.
const baggage_key_cell = u8(2)

fn baggage_key() context.Key {
	return voidptr(&baggage_key_cell)
}

// context_with_baggage returns `ctx` carrying `baggage`, which replaces any it
// had.
pub fn context_with_baggage(ctx context.Context, baggage Baggage) context.Context {
	return context.with_value(ctx, baggage_key(), baggage)
}

// baggage_from_context returns the baggage `ctx` carries, empty if none.
pub fn baggage_from_context(ctx context.Context) Baggage {
	if value := ctx.value(baggage_key()) {
		if value is Baggage {
			return value
		}
	}
	return Baggage{}
}

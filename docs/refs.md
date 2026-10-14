# Refs

A span often needs to say which data an operation used, such as the customer
an agent's tool call looked up, without the data reaching the telemetry
backend. A ref is a short, stable name for a value: the same value gives the
same ref, in any service and any language that follows the same rules, and the
ref doesn't reveal the value.

<!-- snippet: docs/snippets/refs.v#refs -->
```v
// tool_span_attributes names a tool call's arguments in its span without
// putting them there: an `hmac:` ref over their canonical JSON, keyed by
// OTEL_REF_KEY.
fn tool_span_attributes(refs ref.Refs, tool string, args_json string) ![]otel.KeyValue {
	mut attrs := [otel.string_attr('gen_ai.tool.name', tool)]
	args := ref.from_json(json2.decode[json2.Any](args_json)!)!
	if kv := refs.attribute('tool.args_ref', args) {
		attrs << kv
	}
	return attrs
}
```

An engineer with the key makes the ref of a value they know, such as
`{"email": "alice@example.com"}`, and searches the traces for it.
[examples/refs](../examples/refs) does that end to end.

## Modes

| Mode | Ref | When |
|------|-----|------|
| `.hmac` (default) | `hmac:<hex>` | Anything that may hold personal data. |
| `.plain` | `sha256:<hex>` | Short stable names, and no key to manage. |
| `.off` | none | Refs turned off: helpers return `''` or none, and no attribute is added. |

`refs.plain(v)` makes a `sha256:` ref in `hmac` mode too, for values that aren't
sensitive, such as a prompt's fixed prefix.

## Keys

`Refs.new(key: …)` takes the key in code; otherwise `OTEL_REF_KEY`, hex, at
least 32 bytes (`openssl rand -hex 32`). Keep it as you would a password: with
it, anyone can test guesses against your refs.

With no key at all, `Refs.new` makes a random one, says so on stderr, and refs
then match only within the process. A malformed key is an error, not a random
key: refs no one can look up are worse than none.

## Length

`length` is the number of hex characters kept: 16 to 64 in steps of 8, 32 (128
bits) by default. 16 is enough to find a ref in your traces, not to prove a
value from one; 64 is the whole digest.

## Canonical JSON

A ref is computed over the value's canonical JSON, RFC 8785 (JCS): no spaces,
object keys sorted by their UTF-16 code units, strings escaped as JavaScript's
`JSON.stringify` does, numbers in JavaScript's shortest form. So key order and
spacing don't change a ref, and any JCS implementation agrees with this one.

A ref takes a `ref.Value`: null, bool, a number, a string, an array or a map of
them. `ref.from_json` converts a decoded `json2.Any`, such as a tool call's
arguments; `ref.from_struct` converts a struct through its JSON form, so its
`@[json]` names and `@[skip]` fields apply:

<!-- snippet: docs/snippets/refs.v#struct -->
```v
struct Invoice {
	customer string
	amount   int
	note     string @[skip]
}

// invoice_ref names an invoice by its JSON form: `@[skip]` fields don't count.
fn invoice_ref(refs ref.Refs, inv Invoice) !string {
	return refs.ref(ref.from_struct(inv)!)!
}
```

JSON's numbers are floats, so an integer above 2⁵³ passed through JSON is
rounded, as JCS does; build the value with `i64(n)` to keep it exact.

`ref/testdata/vectors.json` holds refs made by Python's `hmac` and
`json.dumps(sort_keys=True)` for ASCII values, which V's refs match;
`ref/testdata/check_vectors.py` checks them from Python. For non-ASCII text and
floats written with an exponent, Python's `json.dumps` differs from JCS, so a
Python service needs a JCS encoder to agree there.

## What a ref doesn't protect

- **Small sets.** Without the key nobody can test guesses, but anyone with it
  can: a ref of a yes/no value or a status code is as good as the value to them.
- **Lengths and counts.** Attributes beside a ref (a list's length, a field's
  presence) can tell about the value.
- **Plain refs.** `sha256:` refs of guessable values (emails, account numbers)
  are reversed by hashing guesses; use `hmac` for those.

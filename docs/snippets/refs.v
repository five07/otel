module main

import json2
import five07.otel
import five07.otel.ref

// snippet: refs
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

// end snippet

// snippet: struct
struct Invoice {
	customer string
	amount   int
	note     string @[skip]
}

// invoice_ref names an invoice by its JSON form: `@[skip]` fields don't count.
fn invoice_ref(refs ref.Refs, inv Invoice) !string {
	return refs.ref(ref.from_struct(inv)!)!
}

// end snippet

// snippet: user
// tag_user names the signed-in user on `span` by a ref of their account ID,
// so one user's requests can be found across traces and services. The ID
// comes from the session or token; the session ID or token itself changes
// on rotation and is a credential, so it isn't what's hashed.
fn tag_user(refs ref.Refs, span otel.Span, account_id string) {
	if kv := refs.attribute('user.ref', account_id) {
		span.set_attributes(kv)
	}
}
// end snippet

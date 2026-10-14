module ref

import json2

// Null is JSON's `null`.
pub struct Null {}

// null is the `Null` value.
pub const null = Null{}

// Value is what a ref is made from: a JSON value. `int` is there so a literal
// such as `42` can be passed as is; it is written as the integer it is.
pub type Value = Null | bool | int | i64 | f64 | string | []Value | map[string]Value

// from_json converts a decoded `json2.Any`, such as a tool call's arguments,
// into a `Value`. JSON's numbers are floats, as JCS reads them. A time, which
// JSON doesn't have, is an error.
pub fn from_json(a json2.Any) !Value {
	return match a {
		json2.Null { null }
		bool { a }
		string { a }
		f64 { a }
		f32 { f64(a) }
		i64 { a }
		int { i64(a) }
		i32 { i64(a) }
		i16 { i64(a) }
		i8 { i64(a) }
		u64 {
			if a <= u64(max_i64) { Value(i64(a)) } else { Value(f64(a)) }
		}
		u32 { i64(a) }
		u16 { i64(a) }
		u8 { i64(a) }
		[]json2.Any { Value(a.map(from_json(it)!)) }
		map[string]json2.Any {
			mut m := map[string]Value{}
			for k, v in a {
				m[k] = from_json(v)!
			}
			Value(m)
		}
		else { error('a ${a.type_name()} is not a JSON value') }
	}
}

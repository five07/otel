module otel

// Value is an attribute's value: one of the types OpenTelemetry defines, a
// string, bool, 64-bit integer or float, or a list of one of those.
pub type Value = string | bool | i64 | f64 | []string | []bool | []i64 | []f64

// str returns the value as text: `books`, `3`, `true`, and a list as `[a, b]`,
// with strings unquoted. Tests compare attributes with it.
pub fn (v Value) str() string {
	return match v {
		string { v }
		bool { v.str() }
		i64 { v.str() }
		f64 { v.str() }
		[]string { '[' + v.join(', ') + ']' }
		[]bool { '[' + v.map(it.str()).join(', ') + ']' }
		[]i64 { '[' + v.map(it.str()).join(', ') + ']' }
		[]f64 { '[' + v.map(it.str()).join(', ') + ']' }
	}
}

// KeyValue is an attribute: a key, such as `http.request.method`, and its value.
// The helpers (`string_attr` and the others) make one with the value typed.
pub struct KeyValue {
pub:
	key   string
	value Value
}

// string_attr makes a string attribute.
pub fn string_attr(key string, value string) KeyValue {
	return KeyValue{
		key:   key
		value: value
	}
}

// bool_attr makes a bool attribute.
pub fn bool_attr(key string, value bool) KeyValue {
	return KeyValue{
		key:   key
		value: value
	}
}

// int_attr makes an integer attribute from an `int`; OpenTelemetry's integers
// are 64-bit, so it is stored as an `i64`.
pub fn int_attr(key string, value int) KeyValue {
	return KeyValue{
		key:   key
		value: i64(value)
	}
}

// i64_attr makes an integer attribute.
pub fn i64_attr(key string, value i64) KeyValue {
	return KeyValue{
		key:   key
		value: value
	}
}

// f64_attr makes a float attribute.
pub fn f64_attr(key string, value f64) KeyValue {
	return KeyValue{
		key:   key
		value: value
	}
}

// strings_attr makes a list-of-strings attribute. It keeps a copy, so later
// changes to `values` don't reach the attribute.
pub fn strings_attr(key string, values []string) KeyValue {
	return KeyValue{
		key:   key
		value: values.clone()
	}
}

// bools_attr makes a list-of-bools attribute, keeping a copy.
pub fn bools_attr(key string, values []bool) KeyValue {
	return KeyValue{
		key:   key
		value: values.clone()
	}
}

// ints_attr makes a list-of-integers attribute from `int`s, stored as `i64`s.
pub fn ints_attr(key string, values []int) KeyValue {
	return KeyValue{
		key:   key
		value: values.map(i64(it))
	}
}

// i64s_attr makes a list-of-integers attribute, keeping a copy.
pub fn i64s_attr(key string, values []i64) KeyValue {
	return KeyValue{
		key:   key
		value: values.clone()
	}
}

// f64s_attr makes a list-of-floats attribute, keeping a copy.
pub fn f64s_attr(key string, values []f64) KeyValue {
	return KeyValue{
		key:   key
		value: values.clone()
	}
}

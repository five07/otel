module ref

import json2
import math
import os
import five07.otel

const key_hex = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'

fn fixed_key() []u8 {
	mut k := []u8{}
	for i in 0 .. 32 {
		k << u8(i)
	}
	return k
}

fn test_the_python_vectors_match() {
	// made by testdata/check_vectors.py, as harness-trace-lab makes refs
	data := json2.decode[json2.Any](os.read_file(os.join_path(@DIR, 'testdata', 'vectors.json'))!)!.as_map()
	assert (data['key_hex'] or { '' }).str() == key_hex
	cases := (data['cases'] or { json2.Any([]json2.Any{}) }).as_array()
	assert cases.len == 90
	for c in cases {
		m := c.as_map()
		mode := if (m['mode'] or { '' }).str() == 'hmac' { Mode.hmac } else { Mode.plain }
		length := (m['length'] or { 0 }).int()
		refs := Refs.new(mode: mode, length: length, key: fixed_key())!
		v := from_json(m['input'] or { json2.Any(json2.Null{}) })!
		assert canonical(v)! == (m['canonical'] or { '' }).str()
		assert refs.ref(v)! == (m['ref'] or { '' }).str()
	}
}

fn test_default_is_hmac_with_32_hex_characters() {
	refs := Refs.new(key: fixed_key())!
	r := refs.ref('alice@example.com')!
	assert r == 'hmac:6fe27db8c6e7931b32acaa3a54136e7f'
	// the same value gives the same ref; another value, another
	assert refs.ref('alice@example.com')! == r
	assert refs.ref('bob@example.com')! != r
	// map order doesn't matter
	a := Value({
		'x': Value(1)
		'y': Value(2)
	})
	b := Value({
		'y': Value(2)
		'x': Value(1)
	})
	assert refs.ref(a)! == refs.ref(b)!
}

fn test_another_key_gives_other_refs() {
	mut other := fixed_key()
	other[0] = 0xff
	a := Refs.new(key: fixed_key())!
	b := Refs.new(key: other)!
	assert a.ref('alice@example.com')! != b.ref('alice@example.com')!
	// plain refs need no key, so they agree
	assert a.plain('prefix')! == b.plain('prefix')!
	assert a.plain('prefix')!.starts_with('sha256:')
}

fn test_modes() {
	plain := Refs.new(mode: .plain)!
	assert plain.ref('x')!.starts_with('sha256:')
	assert plain.ref('x')! == plain.plain('x')!
	off := Refs.new(mode: .off)!
	assert off.ref('x')! == ''
	assert off.plain('x')! == ''
	assert off.attribute('tool.args_ref', 'x') == none
	assert off.plain_attribute('k', 'x') == none
}

fn test_attributes() {
	refs := Refs.new(key: fixed_key(), length: 16)!
	kv := refs.attribute('tool.args_ref', 'alice@example.com')?
	assert kv == otel.string_attr('tool.args_ref', 'hmac:6fe27db8c6e7931b')
	assert refs.plain_attribute('context.prefix_ref', 'p')?.key == 'context.prefix_ref'
	// a value canonical JSON can't write gives no attribute
	nan := math.nan()
	assert refs.attribute('k', nan) == none
}

fn test_lengths() {
	for length in [16, 24, 32, 40, 48, 56, 64] {
		refs := Refs.new(key: fixed_key(), length: length)!
		assert refs.ref('v')!.len == 'hmac:'.len + length
	}
	for length in [0, 8, 15, 17, 33, 72] {
		if _ := Refs.new(key: fixed_key(), length: length) {
			assert false, 'length ${length} was taken'
		}
	}
}

fn test_keys_from_config_and_the_environment() {
	os.unsetenv('OTEL_REF_KEY')
	if _ := Refs.new(key: [u8(1), 2, 3]) {
		assert false, 'a 3-byte key was taken'
	}
	// unset: a random key, with a warning
	r1, w1 := new_refs()!
	r2, _ := new_refs()!
	assert w1 == ['no OTEL_REF_KEY: hmac refs use a random key, and match only within this process']
	assert r1.ref('v')! != r2.ref('v')!
	// set: refs match across processes
	os.setenv('OTEL_REF_KEY', key_hex, true)
	from_env, w2 := new_refs()!
	assert w2.len == 0
	assert from_env.ref('alice@example.com')! == 'hmac:6fe27db8c6e7931b32acaa3a54136e7f'
	// a malformed key is an error, not a random key
	for bad in ['zz', '0001'] {
		os.setenv('OTEL_REF_KEY', bad, true)
		if _ := Refs.new() {
			assert false, 'OTEL_REF_KEY `${bad}` was taken'
		}
	}
	// plain and off need no key
	_ := Refs.new(mode: .plain)!
	os.unsetenv('OTEL_REF_KEY')
}

struct Recipient {
	city string
}

struct Payment {
	to        string
	amount    int
	currency  string @[json: 'ccy']
	note      string @[skip]
	tags      []string
	recipient Recipient
}

fn test_from_struct_uses_the_json_form() {
	p := Payment{
		to:        'alice@example.com'
		amount:    120
		currency:  'EUR'
		note:      'left out'
		tags:      ['b', 'a']
		recipient: Recipient{'Lyon'}
	}
	v := from_struct(p)!
	assert canonical(v)! == '{"amount":120,"ccy":"EUR","recipient":{"city":"Lyon"},"tags":["b","a"],"to":"alice@example.com"}'
	// a skipped field doesn't change the ref
	refs := Refs.new(key: fixed_key())!
	assert refs.ref(v)! == refs.ref(from_struct(Payment{
		...p
		note: 'other'
	})!)!
	assert refs.ref(v)! != refs.ref(from_struct(Payment{
		...p
		amount: 121
	})!)!
}

module ref

import json2
import math

fn test_rfc_8785_numbers() {
	// RFC 8785, appendix B: IEEE 754 bit patterns and their canonical text
	for bits, want in {
		u64(0x0000000000000000): '0'
		0x8000000000000000:      '0'
		0x0000000000000001:      '5e-324'
		0x8000000000000001:      '-5e-324'
		0x7fefffffffffffff:      '1.7976931348623157e+308'
		0xffefffffffffffff:      '-1.7976931348623157e+308'
		0x4340000000000000:      '9007199254740992'
		0xc340000000000000:      '-9007199254740992'
		0x4430000000000000:      '295147905179352830000'
		0x44b52d02c7e14af5:      '9.999999999999997e+22'
		0x44b52d02c7e14af6:      '1e+23'
		0x44b52d02c7e14af7:      '1.0000000000000001e+23'
		0x444b1ae4d6e2ef4e:      '999999999999999700000'
		0x444b1ae4d6e2ef4f:      '999999999999999900000'
		0x444b1ae4d6e2ef50:      '1e+21'
		0x3eb0c6f7a0b5ed8c:      '9.999999999999997e-7'
		0x3eb0c6f7a0b5ed8d:      '0.000001'
		0x41b3de4355555553:      '333333333.3333332'
		0x41b3de4355555554:      '333333333.33333325'
		0x41b3de4355555555:      '333333333.3333333'
		0x41b3de4355555556:      '333333333.3333334'
		0x41b3de4355555557:      '333333333.33333343'
		0xbecbf647612f3696:      '-0.0000033333333333333333'
		0x43143ff3c1cb0959:      '1424953923781206.2'
	} {
		got := format_number(math.f64_from_bits(bits))!
		assert got == want, '${bits:016x}: got ${got}'
	}
	for bits in [u64(0x7fffffffffffffff), 0x7ff0000000000000, 0xfff0000000000000] {
		if _ := format_number(math.f64_from_bits(bits)) {
			assert false, '${bits:016x} was written'
		}
	}
}

fn test_more_numbers() {
	for f, want in {
		0.1:     '0.1'
		1.0:     '1'
		-1.5:    '-1.5'
		100.0:   '100'
		1e20:    '100000000000000000000'
		1e-6:    '0.000001'
		1e-7:    '1e-7'
		1.5e-7:  '1.5e-7'
		123e-20: '1.23e-18'
		4.35:    '4.35'
		0.002:   '0.002'
		1e30:    '1e+30'
	} {
		assert format_number(f)! == want, '${f}'
	}
	assert canonical(42)! == '42'
	assert canonical(i64(-9_007_199_254_740_993))! == '-9007199254740993'
}

fn test_rfc_8785_key_order() {
	// RFC 8785, 3.2.3: UTF-16 order puts U+1F600 (a surrogate pair) before U+FB33
	mut m := map[string]Value{}
	for k in ['\u20ac', '\r', '\ufb33', '1', '😀', '\u0080', '\u00f6'] {
		m[k] = 'x'
	}
	got := canonical(m)!
	assert got == '{"\\r":"x","1":"x","\u0080":"x","\u00f6":"x","\u20ac":"x","😀":"x","\ufb33":"x"}'
}

fn test_rfc_8785_example() {
	// RFC 8785, 3.2.4
	input := '{"numbers": [333333333.33333329, 1E30, 4.50, 2e-3, 0.000000000000000000000000001], "string": "\\u20ac$\\u000F\\u000aA\'\\u0042\\u0022\\u005c\\\\\\"\\/", "literals": [null, true, false]}'
	v := from_json(json2.decode[json2.Any](input)!)!
	assert canonical(v)! == '{"literals":[null,true,false],"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27],"string":"€$\\u000f\\nA\'B\\"\\\\\\\\\\"/"}'
}

fn test_strings_are_escaped_as_json_stringify_does() {
	assert canonical('a"b\\c')! == '"a\\"b\\\\c"'
	assert canonical('\b\t\n\f\r')! == '"\\b\\t\\n\\f\\r"'
	assert canonical('\x01\x1f\x7f')! == '"\\u0001\\u001f\x7f"'
	assert canonical('café / ✓')! == '"café / ✓"'
	if _ := canonical([u8(0xff), 0xfe].bytestr()) {
		assert false, 'text that is not UTF-8 was written'
	}
}

fn test_nesting_and_literals() {
	v := Value({
		'z': Value([Value(1), 'two', null, true, false])
		'a': Value(map[string]Value{})
		'm': Value([]Value{})
	})
	assert canonical(v)! == '{"a":{},"m":[],"z":[1,"two",null,true,false]}'
}

fn test_from_json_rejects_what_json_lacks() {
	assert canonical(from_json(json2.Any(u64(max_u64)))!)! == '18446744073709552000'
	assert canonical(from_json(json2.Any(u64(5)))!)! == '5'
}

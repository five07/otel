module ref

import encoding.utf8
import math
import strconv
import strings

// canonical writes `v` as RFC 8785 (JCS) canonical JSON: no spaces, object keys
// sorted by their UTF-16 code units, strings escaped as JavaScript's
// `JSON.stringify` does, numbers in JavaScript's shortest form. Equal values
// give equal text, in any language that follows the RFC. NaN, infinities and
// text that isn't UTF-8 are errors. An `i64` is written exactly; above 2⁵³, a
// JavaScript implementation would round it.
pub fn canonical(v Value) !string {
	mut sb := strings.new_builder(64)
	write_value(mut sb, v)!
	return sb.str()
}

fn write_value(mut sb strings.Builder, v Value) ! {
	match v {
		Null {
			sb.write_string('null')
		}
		bool {
			sb.write_string(if v { 'true' } else { 'false' })
		}
		int {
			sb.write_string(v.str())
		}
		i64 {
			sb.write_string(v.str())
		}
		f64 {
			sb.write_string(format_number(v)!)
		}
		string {
			write_string(mut sb, v)!
		}
		[]Value {
			sb.write_u8(`[`)
			for i, item in v {
				if i > 0 {
					sb.write_u8(`,`)
				}
				write_value(mut sb, item)!
			}
			sb.write_u8(`]`)
		}
		map[string]Value {
			mut keys := []string{cap: v.len}
			for k, _ in v {
				keys << k
			}
			keys.sort_with_compare(fn (a &string, b &string) int {
				return compare_utf16(*a, *b)
			})
			sb.write_u8(`{`)
			for i, k in keys {
				if i > 0 {
					sb.write_u8(`,`)
				}
				write_string(mut sb, k)!
				sb.write_u8(`:`)
				write_value(mut sb, v[k] or { null })!
			}
			sb.write_u8(`}`)
		}
	}
}

// write_string quotes `s` as `JSON.stringify` does: `"` and `\` escaped, the
// control characters below space as `\b \t \n \f \r` or `\u00xx`, the rest as
// UTF-8.
fn write_string(mut sb strings.Builder, s string) ! {
	if !utf8.validate_str(s) {
		return error('canonical JSON is UTF-8 text only')
	}
	sb.write_u8(`"`)
	for c in s {
		match c {
			`"` { sb.write_string('\\"') }
			`\\` { sb.write_string('\\\\') }
			`\b` { sb.write_string('\\b') }
			`\t` { sb.write_string('\\t') }
			`\n` { sb.write_string('\\n') }
			`\f` { sb.write_string('\\f') }
			`\r` { sb.write_string('\\r') }
			else {
				if c < 0x20 {
					sb.write_string('\\u00')
					sb.write_u8('0123456789abcdef'[c >> 4])
					sb.write_u8('0123456789abcdef'[c & 0xf])
				} else {
					sb.write_u8(c)
				}
			}
		}
	}
	sb.write_u8(`"`)
}

// compare_utf16 orders two strings by their UTF-16 code units, as RFC 8785
// sorts keys: code point order, except that characters above U+FFFF (written
// as surrogates, D800 to DFFF) come before U+E000 to U+FFFF.
fn compare_utf16(a string, b string) int {
	ua := utf16_units(a)
	ub := utf16_units(b)
	for i in 0 .. math.min(ua.len, ub.len) {
		if ua[i] != ub[i] {
			return if ua[i] < ub[i] { -1 } else { 1 }
		}
	}
	return ua.len - ub.len
}

fn utf16_units(s string) []u16 {
	mut out := []u16{cap: s.len}
	for r in s.runes() {
		cp := u32(r)
		if cp >= 0x10000 {
			c := cp - 0x10000
			out << u16(0xd800 + (c >> 10))
			out << u16(0xdc00 + (c & 0x3ff))
		} else {
			out << u16(cp)
		}
	}
	return out
}

// format_number writes `f` as JavaScript's `Number.prototype.toString` does,
// which RFC 8785 requires: the shortest digits that read back as `f`, as an
// integer up to 21 digits, a decimal down to 0.000001, else with an exponent.
fn format_number(f f64) !string {
	if math.is_nan(f) || math.is_inf(f, 0) {
		return error('canonical JSON has no NaN or infinity')
	}
	if f == 0 {
		return '0'
	}
	// Ryu's shortest form: `[-]d[.ddd]e±xx`
	sci := strconv.ftoa_64(f)
	negative := sci.starts_with('-')
	body := if negative { sci[1..] } else { sci }
	mantissa := body.all_before('e')
	mut digits := mantissa.replace('.', '').trim_right('0')
	if digits == '' {
		digits = '0'
	}
	k := digits.len
	// the value is 0.digits × 10^n
	n := body.all_after('e').int() + 1
	sign := if negative { '-' } else { '' }
	if k <= n && n <= 21 {
		return sign + digits + '0'.repeat(n - k)
	}
	if 0 < n && n <= 21 {
		return sign + digits[..n] + '.' + digits[n..]
	}
	if -6 < n && n <= 0 {
		return sign + '0.' + '0'.repeat(-n) + digits
	}
	e := n - 1
	exp := if e < 0 { 'e-${-e}' } else { 'e+${e}' }
	return sign + if k == 1 { digits } else { digits[..1] + '.' + digits[1..] } + exp
}

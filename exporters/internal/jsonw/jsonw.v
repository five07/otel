// Package jsonw writes JSON whose objects keep their key order, on one line or
// indented, for otel's exporters.
module jsonw

import encoding.utf8
import math
import strings

// Node is a JSON value in the making: an encoded scalar, an object whose keys
// keep their order, or an array.
pub type Node = Raw | Obj | Arr

pub struct Raw {
pub:
	text string
}

pub struct Obj {
mut:
	pairs []Pair
}

struct Pair {
	key   string
	value Node
}

pub struct Arr {
pub:
	items []Node
}

// add appends `key` and its value.
pub fn (mut o Obj) add(key string, value Node) {
	o.pairs << Pair{key, value}
}

// str_node is a JSON string.
pub fn str_node(s string) Node {
	return Raw{quote(s)}
}

// int_node is a JSON number from an integer.
pub fn int_node(n i64) Node {
	return Raw{n.str()}
}

// float_node writes a float; JSON has no NaN or infinity, so they are strings.
pub fn float_node(f f64) Node {
	if math.is_nan(f) {
		return str_node('NaN')
	}
	if math.is_inf(f, 0) {
		return str_node(if f > 0 { 'Infinity' } else { '-Infinity' })
	}
	return Raw{f.str()}
}

// write_node writes `n` on one line when `indent` is -1, else indented by two
// spaces a level, starting at `indent`.
pub fn write_node(mut sb strings.Builder, n Node, indent int) {
	match n {
		Raw {
			sb.write_string(n.text)
		}
		Obj {
			if n.pairs.len == 0 {
				sb.write_string('{}')
				return
			}
			sb.write_u8(`{`)
			for i, p in n.pairs {
				if i > 0 {
					sb.write_u8(`,`)
				}
				newline(mut sb, indent, 1)
				sb.write_string(quote(p.key))
				sb.write_string(if indent < 0 { ':' } else { ': ' })
				write_node(mut sb, p.value, if indent < 0 { -1 } else { indent + 1 })
			}
			newline(mut sb, indent, 0)
			sb.write_u8(`}`)
		}
		Arr {
			if n.items.len == 0 {
				sb.write_string('[]')
				return
			}
			sb.write_u8(`[`)
			for i, item in n.items {
				if i > 0 {
					sb.write_u8(`,`)
				}
				newline(mut sb, indent, 1)
				write_node(mut sb, item, if indent < 0 { -1 } else { indent + 1 })
			}
			newline(mut sb, indent, 0)
			sb.write_u8(`]`)
		}
	}
}

fn newline(mut sb strings.Builder, indent int, extra int) {
	if indent >= 0 {
		sb.write_u8(`\n`)
		sb.write_string('  '.repeat(indent + extra))
	}
}

// quote writes `s` as a JSON string. Text that isn't UTF-8 has its bytes from
// 0x80 written as `\u00xx`, so the line stays valid JSON.
pub fn quote(s string) string {
	valid := utf8.validate_str(s)
	mut sb := strings.new_builder(s.len + 2)
	sb.write_u8(`"`)
	for c in s {
		match c {
			`"` {
				sb.write_string('\\"')
			}
			`\\` {
				sb.write_string('\\\\')
			}
			`\n` {
				sb.write_string('\\n')
			}
			`\r` {
				sb.write_string('\\r')
			}
			`\t` {
				sb.write_string('\\t')
			}
			else {
				if c < 0x20 || (!valid && c >= 0x80) {
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
	return sb.str()
}

// encode writes `n` on one line, or indented by two spaces when `pretty`.
pub fn encode(n Node, pretty bool) string {
	mut sb := strings.new_builder(256)
	write_node(mut sb, n, if pretty { 0 } else { -1 })
	return sb.str()
}

module otel

import net.urllib

const upper_hex_digits = '0123456789ABCDEF'

// max_baggage_members is the most entries a `Baggage` holds, as the W3C
// Baggage specification sets it.
pub const max_baggage_members = 64

// max_baggage_bytes is the longest a `baggage` header may be.
pub const max_baggage_bytes = 8192

// BaggageProperty is metadata on a baggage entry: a key, and maybe a value.
pub struct BaggageProperty {
pub:
	key   string
	value ?string
}

// BaggageMember is one baggage entry: a key, its value, and its properties.
pub struct BaggageMember {
pub:
	key        string
	value      string
	properties []BaggageProperty
}

// Baggage is the name and value pairs a request carries to every service it
// reaches, in the `baggage` header, such as a tenant or a user tier. It is
// sent as is to every service downstream, so it must not hold secrets. It never
// changes: `set` and `delete` return a new one.
pub struct Baggage {
	members []BaggageMember
}

// Baggage.parse reads a `baggage` header: `key=value;property` entries joined
// by commas, values percent-encoded. A key given twice keeps its last value. A
// malformed entry, more than 64 entries, or a header over 8,192 bytes is an
// error, and the caller drops the whole header.
pub fn Baggage.parse(header string) !Baggage {
	if header.len > max_baggage_bytes {
		return error('a baggage header is at most ${max_baggage_bytes} bytes')
	}
	mut b := Baggage{}
	for raw in header.split(',') {
		if raw.trim(' \t') == '' {
			continue
		}
		parts := raw.split(';')
		key, value := parse_baggage_pair(parts[0], true)!
		mut props := []BaggageProperty{}
		for p in parts[1..] {
			if p.trim(' \t') == '' {
				continue
			}
			pkey, pvalue := parse_baggage_pair(p, false)!
			props << BaggageProperty{
				key:   pkey
				value: pvalue
			}
		}
		b = b.with_member(BaggageMember{
			key:        key
			value:      value or { '' }
			properties: props
		})
		if b.members.len > max_baggage_members {
			return error('a baggage header has at most ${max_baggage_members} entries')
		}
	}
	return b
}

// parse_baggage_pair reads `key=value` (or `key`, unless the value is
// required), trimming spaces and tabs and percent-decoding the value. Errors
// don't quote the value, which is the app's data.
fn parse_baggage_pair(s string, value_required bool) !(string, ?string) {
	eq := s.index_u8(`=`)
	if eq < 0 {
		if value_required {
			return error('a baggage entry is `key=value`')
		}
		key := s.trim(' \t')
		check_baggage_key(key)!
		return key, none
	}
	key := s[..eq].trim(' \t')
	check_baggage_key(key)!
	raw := s[eq + 1..].trim(' \t')
	for c in raw {
		if !is_baggage_octet(c) && c != `%` {
			return error('the baggage value of `${key}` has a character it must not')
		}
	}
	value := urllib.path_unescape(raw) or {
		return error('the baggage value of `${key}` has a bad percent-encoding')
	}
	return key, value
}

// get returns the value of `key`, or none.
pub fn (b Baggage) get(key string) ?string {
	m := b.member(key)?
	return m.value
}

// member returns the entry of `key`, with its properties, or none.
pub fn (b Baggage) member(key string) ?BaggageMember {
	for m in b.members {
		if m.key == key {
			return m
		}
	}
	return none
}

// set returns the baggage with `key` set to `value`, replacing any entry with
// that key. The key must be an HTTP token; the value may be any text, and is
// percent-encoded when sent.
pub fn (b Baggage) set(key string, value string, properties ...BaggageProperty) !Baggage {
	check_baggage_key(key)!
	for p in properties {
		check_baggage_key(p.key)!
	}
	return b.with_member(BaggageMember{
		key:        key
		value:      value
		properties: properties
	})
}

// delete returns the baggage without `key`.
pub fn (b Baggage) delete(key string) Baggage {
	return Baggage{
		members: b.members.filter(it.key != key)
	}
}

// len is the number of entries.
pub fn (b Baggage) len() int {
	return b.members.len
}

// members returns the entries, in the order they were first set.
pub fn (b Baggage) members() []BaggageMember {
	return b.members.clone()
}

// str writes the baggage as the `baggage` header does, values percent-encoded.
pub fn (b Baggage) str() string {
	return b.members.map(fn (m BaggageMember) string {
		mut s := '${m.key}=${encode_baggage_value(m.value)}'
		for p in m.properties {
			s += if v := p.value { ';${p.key}=${encode_baggage_value(v)}' } else { ';${p.key}' }
		}
		return s
	}).join(',')
}

fn (b Baggage) with_member(m BaggageMember) Baggage {
	mut members := b.members.clone()
	for i, old in members {
		if old.key == m.key {
			members[i] = m
			return Baggage{
				members: members
			}
		}
	}
	members << m
	return Baggage{
		members: members
	}
}

// check_baggage_key checks a key is an HTTP token: one or more of the letters,
// digits and `!#$%&'*+-.^_`|~`.
fn check_baggage_key(key string) ! {
	if key == '' {
		return error('a baggage key is not empty')
	}
	for c in key {
		if !(c.is_letter() || c.is_digit() || c in [`!`, `#`, `$`, `%`, `&`, `'`, `*`, `+`, `-`,
			`.`, `^`, `_`, `\``, `|`, `~`]) {
			return error("a baggage key is letters, digits and `!#$%&'*+-.^_`|~` only")
		}
	}
}

// is_baggage_octet tells whether a byte may appear in a value as is: printable
// ASCII but space, `"`, `,`, `;` and `\`.
fn is_baggage_octet(c u8) bool {
	return c >= 0x21 && c <= 0x7e && c !in [`"`, `,`, `;`, `\\`]
}

// encode_baggage_value percent-encodes every byte that isn't a baggage octet,
// and `%`, so the value reads back as it was.
fn encode_baggage_value(v string) string {
	mut out := []u8{cap: v.len}
	for c in v {
		if is_baggage_octet(c) && c != `%` {
			out << c
		} else {
			out << `%`
			out << upper_hex_digits[c >> 4]
			out << upper_hex_digits[c & 0xf]
		}
	}
	return out.bytestr()
}

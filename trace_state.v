module otel

// max_trace_state_members is the most entries a `TraceState` holds, as the W3C
// Trace Context sets it.
pub const max_trace_state_members = 32

// TraceStateMember is one `key=value` entry of a `TraceState`.
pub struct TraceStateMember {
pub:
	key   string
	value string
}

// TraceState is the `tracestate` header's list of vendor entries, kept in its
// order: the most recently updated entry first. It never changes: `insert` and
// `delete` return a new one.
pub struct TraceState {
	members []TraceStateMember
}

// TraceState.parse reads a `tracestate` header: `key=value` entries joined by
// commas, with optional spaces and tabs around them; empty entries are skipped.
// A key or value outside the W3C grammar, a key given twice, or more than 32
// entries is an error, and the caller drops the whole header.
pub fn TraceState.parse(header string) !TraceState {
	mut members := []TraceStateMember{}
	for raw in header.split(',') {
		entry := raw.trim(' \t')
		if entry == '' {
			continue
		}
		eq := entry.index_u8(`=`)
		if eq < 0 {
			return error('a tracestate entry is `key=value`')
		}
		key := entry[..eq]
		value := entry[eq + 1..]
		check_trace_state_key(key)!
		check_trace_state_value(value)!
		for m in members {
			if m.key == key {
				return error('a tracestate key appears twice')
			}
		}
		members << TraceStateMember{
			key:   key
			value: value
		}
		if members.len > max_trace_state_members {
			return error('a tracestate has at most ${max_trace_state_members} entries')
		}
	}
	return TraceState{
		members: members
	}
}

// get returns the value of `key`, or none.
pub fn (ts TraceState) get(key string) ?string {
	for m in ts.members {
		if m.key == key {
			return m.value
		}
	}
	return none
}

// insert returns the state with `key` set to `value`, moved to the front, as a
// service does to its own entry before passing the state on. A new entry in a
// full state drops the last one. A key or value outside the W3C grammar is an
// error.
pub fn (ts TraceState) insert(key string, value string) !TraceState {
	check_trace_state_key(key)!
	check_trace_state_value(value)!
	mut members := [TraceStateMember{
		key:   key
		value: value
	}]
	for m in ts.members {
		if m.key != key {
			members << m
		}
	}
	if members.len > max_trace_state_members {
		members = members[..max_trace_state_members].clone()
	}
	return TraceState{
		members: members
	}
}

// delete returns the state without `key`; the same state if it had none.
pub fn (ts TraceState) delete(key string) TraceState {
	return TraceState{
		members: ts.members.filter(it.key != key)
	}
}

// len is the number of entries.
pub fn (ts TraceState) len() int {
	return ts.members.len
}

// members returns the entries, first to last.
pub fn (ts TraceState) members() []TraceStateMember {
	return ts.members.clone()
}

// str writes the state as the `tracestate` header does: `key=value` entries
// joined by commas, first to last; empty for no entries.
pub fn (ts TraceState) str() string {
	return ts.members.map('${it.key}=${it.value}').join(',')
}

// check_trace_state_key checks a key against the W3C grammar: either a simple
// key, a lowercase letter then up to 255 of `a-z 0-9 _ - * /`, or a
// multi-tenant `tenant@system`, a tenant of 1 to 241 of those starting with a
// letter or digit, and a system of 1 to 14 starting with a letter.
fn check_trace_state_key(key string) ! {
	at := key.index_u8(`@`)
	if at < 0 {
		if key == '' || key.len > 256 || !is_lcalpha(key[0])
			|| !key.bytes().all(is_key_char(it)) {
			return error('a tracestate key is a lowercase letter then up to 255 of `a-z 0-9 _ - * /`')
		}
		return
	}
	tenant := key[..at]
	system := key[at + 1..]
	if tenant == '' || tenant.len > 241 || !(is_lcalpha(tenant[0]) || tenant[0].is_digit())
		|| !tenant.bytes().all(is_key_char(it)) || system == '' || system.len > 14
		|| !is_lcalpha(system[0]) || !system.bytes().all(is_key_char(it)) {
		return error('a multi-tenant tracestate key is `tenant@system`: up to 241 and 14 of `a-z 0-9 _ - * /`, the system starting with a letter')
	}
}

// check_trace_state_value checks a value against the W3C grammar: 1 to 256
// printable ASCII characters, but not `,` or `=`, and not ending in a space.
fn check_trace_state_value(value string) ! {
	if value == '' || value.len > 256 || value[value.len - 1] == ` ` {
		return error('a tracestate value is 1 to 256 characters and does not end in a space')
	}
	for c in value {
		if c < 0x20 || c > 0x7e || c == `,` || c == `=` {
			return error('a tracestate value is printable ASCII without `,` or `=`')
		}
	}
}

fn is_lcalpha(c u8) bool {
	return c >= `a` && c <= `z`
}

fn is_key_char(c u8) bool {
	return is_lcalpha(c) || c.is_digit() || c in [`_`, `-`, `*`, `/`]
}

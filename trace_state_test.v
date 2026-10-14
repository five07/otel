module otel

fn test_insert_puts_the_entry_first() {
	// the W3C spec's example: rojo updates its entry, ahead of congo's
	ts := TraceState{}.insert('congo', 't61rcWkgMzE')!.insert('rojo', '00f067aa0ba902b7')!
	assert ts.str() == 'rojo=00f067aa0ba902b7,congo=t61rcWkgMzE'
	assert ts.len() == 2
	assert ts.get('congo')? == 't61rcWkgMzE'
	assert ts.get('nope') == none
}

fn test_insert_moves_an_existing_key_to_the_front() {
	ts := TraceState{}.insert('a', '1')!.insert('b', '2')!.insert('c', '3')!
	assert ts.str() == 'c=3,b=2,a=1'
	moved := ts.insert('a', '4')!
	assert moved.str() == 'a=4,c=3,b=2'
	assert moved.len() == 3
}

fn test_insert_and_delete_leave_the_original_alone() {
	ts := TraceState{}.insert('a', '1')!
	_ := ts.insert('b', '2')!
	_ := ts.insert('a', '9')!
	_ := ts.delete('a')
	assert ts.str() == 'a=1'
}

fn test_delete() {
	ts := TraceState{}.insert('a', '1')!.insert('b', '2')!
	assert ts.delete('a').str() == 'b=2'
	assert ts.delete('nope').str() == 'b=2,a=1'
	assert ts.delete('a').delete('b').str() == ''
}

fn test_a_full_state_drops_the_last_entry() {
	mut ts := TraceState{}
	for i in 0 .. max_trace_state_members {
		ts = ts.insert('k${i}', 'v')!
	}
	assert ts.len() == 32
	assert ts.get('k0')? == 'v'
	ts = ts.insert('new', 'v')!
	assert ts.len() == 32
	assert ts.members()[0].key == 'new'
	assert ts.get('k0') == none
	// updating a key already there drops nothing
	ts = ts.insert('k5', 'w')!
	assert ts.len() == 32
	assert ts.get('k1')? == 'v'
}

fn test_members_is_a_copy() {
	ts := TraceState{}.insert('a', '1')!
	mut ms := ts.members()
	ms << TraceStateMember{
		key:   'b'
		value: '2'
	}
	assert ts.len() == 1
}

fn test_keys_follow_the_grammar() {
	good := ['a', 'z0_-*/', 'a'.repeat(256), 'tenant@system', '0tenant@s', 'a'.repeat(241) + '@' +
		'b'.repeat(14), 'fw529a3039@dt']
	for key in good {
		TraceState{}.insert(key, 'v') or { assert false, '`${key}`: ${err}' }
	}
	bad := ['', 'A', '0abc', '_a', 'a b', 'a.b', 'a'.repeat(257), '@system', 'tenant@', 'tenant@0s',
		'a'.repeat(242) + '@s', 't@' + 'b'.repeat(15), 'a@b@c', 'T@s']
	for key in bad {
		if _ := TraceState{}.insert(key, 'v') {
			assert false, '`${key}` was taken as a key'
		}
	}
}

fn test_values_follow_the_grammar() {
	good := ['v', ' leading space', 'a b', '!"#$%&()*+-./:;<>?@[\\]^_`{|}~', 'x'.repeat(256)]
	for value in good {
		TraceState{}.insert('k', value) or { assert false, '`${value}`: ${err}' }
	}
	bad := ['', 'trailing ', 'a,b', 'a=b', 'tab\there', 'x'.repeat(257), 'café']
	for value in bad {
		if _ := TraceState{}.insert('k', value) {
			assert false, '`${value}` was taken as a value'
		}
	}
}

module otel

fn test_scalar_attributes_keep_their_type() {
	s := string_attr('http.request.method', 'GET')
	assert s.key == 'http.request.method'
	assert s.value is string
	assert s.value as string == 'GET'

	b := bool_attr('cache.hit', true)
	assert b.value is bool
	assert b.value as bool

	n := int_attr('http.response.status_code', 200)
	assert n.value is i64
	assert n.value as i64 == 200

	big := i64_attr('db.rows', 9_007_199_254_740_993)
	assert big.value as i64 == 9_007_199_254_740_993

	f := f64_attr('ratio', 0.25)
	assert f.value is f64
	assert f.value as f64 == 0.25
}

fn test_list_attributes_keep_their_type() {
	assert strings_attr('k', ['a', 'b']).value as []string == ['a', 'b']
	assert bools_attr('k', [true, false]).value as []bool == [true, false]
	assert ints_attr('k', [1, -2]).value as []i64 == [i64(1), -2]
	assert i64s_attr('k', [i64(3)]).value as []i64 == [i64(3)]
	assert f64s_attr('k', [0.5]).value as []f64 == [0.5]
	assert strings_attr('k', []).value as []string == []
}

fn test_list_attributes_are_copies() {
	mut names := ['a', 'b']
	kv := strings_attr('k', names)
	names[0] = 'changed'
	names << 'c'
	assert kv.value as []string == ['a', 'b']

	mut flags := [true]
	bk := bools_attr('k', flags)
	flags[0] = false
	assert bk.value as []bool == [true]

	mut ns := [i64(1)]
	ik := i64s_attr('k', ns)
	ns[0] = 2
	assert ik.value as []i64 == [i64(1)]

	mut fs := [1.0]
	fk := f64s_attr('k', fs)
	fs[0] = 2.0
	assert fk.value as []f64 == [1.0]
}

fn test_attributes_compare_by_value() {
	assert string_attr('k', 'v') == string_attr('k', 'v')
	assert string_attr('k', 'v') != string_attr('k', 'w')
	assert int_attr('k', 1) == i64_attr('k', 1)
	// the same number as an integer and as a float are different values
	assert i64_attr('k', 1) != f64_attr('k', 1.0)
	assert strings_attr('k', ['a']) == strings_attr('k', ['a'])
}

fn test_a_value_reads_as_itself() {
	assert string_attr('k', 'books').value.str() == 'books'
	assert int_attr('k', 3).value.str() == '3'
	assert bool_attr('k', true).value.str() == 'true'
	assert f64_attr('k', 0.25).value.str() == '0.25'
	assert strings_attr('k', ['a', 'b']).value.str() == '[a, b]'
	assert ints_attr('k', [1, -2]).value.str() == '[1, -2]'
	v := string_attr('k', 'books').value
	assert '${v}' == 'books'
}

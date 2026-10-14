module resource

import os
import five07.otel

fn test_new_keeps_the_last_value_and_sorts() {
	r := Resource.new([otel.string_attr('b', '1'), otel.string_attr('a', '2'),
		otel.string_attr('b', '3'), otel.string_attr('', 'dropped')], 'https://opentelemetry.io/schemas/1.26.0')
	assert r.attributes() == [otel.string_attr('a', '2'), otel.string_attr('b', '3')]
	assert r.get('b')? as string == '3'
	assert r.get('c') == none
	assert r.schema_url == 'https://opentelemetry.io/schemas/1.26.0'
}

fn test_attributes_is_a_copy() {
	r := Resource.new([otel.string_attr('a', '1')], '')
	mut attrs := r.attributes()
	attrs << otel.string_attr('b', '2')
	assert r.attributes().len == 1
}

fn test_merge_lets_the_updating_resource_win() {
	old := Resource.new([otel.string_attr('service.name', 'old'), otel.int_attr('a', 1)],
		'')
	updating := Resource.new([otel.string_attr('service.name', 'new'), otel.bool_attr('b', true)], '')
	m := old.merge(updating)!
	assert m.attributes() == [otel.int_attr('a', 1), otel.bool_attr('b', true),
		otel.string_attr('service.name', 'new')]
	// the originals are untouched
	assert old.get('service.name')? as string == 'old'
}

fn test_merge_schema_urls() {
	a := Resource.new([], 'https://opentelemetry.io/schemas/1.26.0')
	b := Resource.new([], 'https://opentelemetry.io/schemas/1.27.0')
	none_ := Resource.new([], '')
	assert a.merge(none_)!.schema_url == a.schema_url
	assert none_.merge(a)!.schema_url == a.schema_url
	assert a.merge(a)!.schema_url == a.schema_url
	if _ := a.merge(b) {
		assert false, 'different schema URLs merged'
	}
}

fn test_sdk_attributes() {
	r := sdk()
	assert r.get('telemetry.sdk.name')? as string == 'five07.otel'
	assert r.get('telemetry.sdk.language')? as string == 'v'
	assert r.get('telemetry.sdk.version')? as string == otel.version
}

fn test_parse_resource_attributes() {
	assert parse_resource_attributes('')! == []
	assert parse_resource_attributes('  ')! == []
	assert parse_resource_attributes('a=1, b = two words ,c=%2C%3D%20x+y,d=')! == [
		otel.string_attr('a', '1'),
		otel.string_attr('b', 'two words'),
		otel.string_attr('c', ',= x+y'),
		otel.string_attr('d', ''),
	]
	bad := {
		'a=1,b':       'OTEL_RESOURCE_ATTRIBUTES: entry 2 has no `=`'
		'a=1,=2':      'OTEL_RESOURCE_ATTRIBUTES: entry 2 has no key'
		'a=%zzsecret': 'OTEL_RESOURCE_ATTRIBUTES: the value of `a` has a bad percent-encoding'
	}
	for s, want in bad {
		if _ := parse_resource_attributes(s) {
			assert false, '`${s}` was read'
		} else {
			assert err.msg() == want
		}
	}
}

fn test_the_environment_and_its_precedence() {
	os.setenv('OTEL_RESOURCE_ATTRIBUTES', 'service.name=from-attrs,deployment.environment.name=prod',
		true)
	os.unsetenv('OTEL_SERVICE_NAME')
	r := default()!
	assert r.get('service.name')? as string == 'from-attrs'
	assert r.get('deployment.environment.name')? as string == 'prod'
	assert r.get('telemetry.sdk.name')? as string == 'five07.otel'

	// OTEL_SERVICE_NAME wins over OTEL_RESOURCE_ATTRIBUTES
	os.setenv('OTEL_SERVICE_NAME', 'checkout', true)
	assert default()!.get('service.name')? as string == 'checkout'

	// and the app's own attributes win over both
	app := default()!.merge(Resource.new([otel.string_attr('service.name', 'from-code')],
		''))!
	assert app.get('service.name')? as string == 'from-code'
	assert app.get('deployment.environment.name')? as string == 'prod'

	// a malformed variable is an error, and none of it is used
	os.setenv('OTEL_RESOURCE_ATTRIBUTES', 'deployment.environment.name=prod,oops', true)
	if _ := default() {
		assert false, 'a malformed OTEL_RESOURCE_ATTRIBUTES was used'
	}
	fallback := default_without_env()
	assert fallback.get('deployment.environment.name') == none

	os.unsetenv('OTEL_RESOURCE_ATTRIBUTES')
	os.unsetenv('OTEL_SERVICE_NAME')
}

fn test_without_a_service_name_it_is_unknown_service() {
	os.unsetenv('OTEL_RESOURCE_ATTRIBUTES')
	os.unsetenv('OTEL_SERVICE_NAME')
	name := default()!.get('service.name')? as string
	assert name.starts_with('unknown_service:')
	assert name.len > 'unknown_service:'.len
}

module otel

import context

fn test_parse_reads_entries_and_properties() {
	b := Baggage.parse('userId=alice, serverNode = DF%2028 ,isProduction=false;ttl=60;private')!
	assert b.len() == 3
	assert b.get('userId')? == 'alice'
	assert b.get('serverNode')? == 'DF 28'
	m := b.member('isProduction')?
	assert m.value == 'false'
	assert m.properties.len == 2
	assert m.properties[0].key == 'ttl'
	assert m.properties[0].value? == '60'
	assert m.properties[1].key == 'private'
	assert m.properties[1].value == none
	assert b.get('nope') == none
}

fn test_str_percent_encodes_and_round_trips() {
	b := Baggage{}.set('tenant', 'acme corp')!.set('path', '/a,b;c=d%e\\"')!.set('emoji',
		'café')!
	header := b.str()
	assert header == 'tenant=acme%20corp,path=/a%2Cb%3Bc=d%25e%5C%22,emoji=caf%C3%A9'
	back := Baggage.parse(header)!
	assert back.get('tenant')? == 'acme corp'
	assert back.get('path')? == '/a,b;c=d%e\\"'
	assert back.get('emoji')? == 'café'
}

fn test_properties_are_written_back() {
	b := Baggage{}.set('k', 'v', BaggageProperty{ key: 'flag' }, BaggageProperty{
		key:   'ttl'
		value: '60'
	})!
	assert b.str() == 'k=v;flag;ttl=60'
	assert Baggage.parse(b.str())!.str() == 'k=v;flag;ttl=60'
}

fn test_set_replaces_and_delete_removes() {
	b := Baggage{}.set('a', '1')!.set('b', '2')!
	c := b.set('a', '3')!
	assert c.str() == 'a=3,b=2'
	assert b.str() == 'a=1,b=2'
	assert c.delete('a').str() == 'b=2'
	// a key given twice in a header keeps its last value
	assert Baggage.parse('a=1,a=2')!.str() == 'a=2'
}

fn test_bad_keys_and_headers_are_errors() {
	for key in ['', 'a b', 'a,b', 'a;b', 'a=b', 'café'] {
		if _ := Baggage{}.set(key, 'v') {
			assert false, 'key `${key}` was taken'
		}
	}
	mut too_many := []string{}
	for i in 0 .. 65 {
		too_many << 'k${i}=v'
	}
	for header in ['novalue', '=v', 'k=a b', 'k=%zz', 'k=v;=p', too_many.join(','),
		'k=' + 'x'.repeat(8192)] {
		if _ := Baggage.parse(header) {
			assert false, '`${header#[..40]}` was read'
		}
	}
	// exactly at the limits is fine
	mut sixty_four := []string{}
	for i in 0 .. 64 {
		sixty_four << 'k${i}=v'
	}
	assert Baggage.parse(sixty_four.join(','))!.len() == 64
}

fn test_errors_do_not_quote_values() {
	if _ := Baggage.parse('secret=hunter2 x') {
		assert false
	} else {
		assert !err.msg().contains('hunter2')
	}
}

fn test_baggage_goes_in_and_out_of_a_context() {
	assert baggage_from_context(context.background()).len() == 0
	b := Baggage{}.set('tenant', 'acme')!
	ctx := context_with_baggage(context.background(), b)
	assert baggage_from_context(ctx).get('tenant')? == 'acme'
	// the span and the baggage keep apart
	ctx2 := context_with_span(ctx, NoopSpan{})
	assert baggage_from_context(ctx2).get('tenant')? == 'acme'
	assert !span_from_context(ctx).span_context().is_valid()
}

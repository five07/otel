module main

import context
import time
import five07.otel
import five07.otel.sdk.trace

fn test_a_library_records_nothing_until_given_a_provider() {
	quiet := Store.new()
	assert quiet.get(context.background(), 'a')! == 'blob:a'
	// snippet: testing
	exporter := trace.InMemoryExporter.new()
	provider := trace.TracerProvider.new(processors: [trace.SimpleSpanProcessor.new(exporter)])!
	store := Store.new(tracer_provider: provider)
	// … run the code, then read the spans back
	// end snippet
	ctx, parent := provider.tracer('app').start(context.background(), 'request')
	store.get(ctx, 'b')!
	store.get(ctx, '') or {}
	at := time.unix(1_700_000_000)
	store.record_statement(ctx, at, 3 * time.millisecond, true)
	parent.end()
	spans := exporter.spans()
	assert spans.map(it.name) == ['blobstore.get', 'blobstore.get', 'SELECT blobs', 'request']
	// snippet: reading
	request := exporter.span('request')?
	get := exporter.span('blobstore.get')?
	assert get.is_child_of(request)
	assert get.attribute('blobstore.bucket')?.str() == 'images'
	// end snippet
	assert spans[0].parent == spans[3].span_context
	assert spans[0].scope.name == 'example.blobstore'
	assert spans[1].status.code == .error
	assert spans[1].events[0].attributes == [otel.string_attr('exception.type', 'MessageError')]
	assert spans[2].start_ns == at.unix_nano()
	assert spans[2].end_ns - spans[2].start_ns == 3_000_000
}

fn test_own_values_travel_with_the_trace() {
	exporter := trace.InMemoryExporter.new()
	provider := trace.TracerProvider.new(processors: [trace.SimpleSpanProcessor.new(exporter)])!
	assert tenant_from(context.background()) == none
	ctx, span := provider.tracer('app').start(with_tenant(context.background(), 'acme'),
		'request')
	assert tenant_from(ctx)? == 'acme'
	assert otel.span_from_context(ctx).span_context() == span.span_context()
	span.end()
}

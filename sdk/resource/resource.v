// Package resource describes the entity that produces telemetry, such as a
// service and its version, as attributes sent with every span.
module resource

import net.urllib
import os
import five07.otel
import five07.otel.semconv

// sdk_name is `telemetry.sdk.name`: the specification asks an SDK that isn't
// the project's own to name itself.
pub const sdk_name = 'five07.otel'

// sdk_language is `telemetry.sdk.language`.
pub const sdk_language = 'v'

// Resource is the set of attributes that describe what made the telemetry,
// with the schema URL of their conventions. Each key appears once. It never
// changes: `merge` returns a new one.
pub struct Resource {
	attributes []otel.KeyValue
pub:
	schema_url string
}

// Resource.new returns a resource with `attributes`. A key given twice keeps
// its last value, and an empty key is dropped.
pub fn Resource.new(attributes []otel.KeyValue, schema_url string) Resource {
	return Resource{
		attributes: dedup(attributes)
		schema_url: schema_url
	}
}

// attributes returns the attributes, sorted by key.
pub fn (r Resource) attributes() []otel.KeyValue {
	return r.attributes.clone()
}

// get returns the value of `key`, or none.
pub fn (r Resource) get(key string) ?otel.Value {
	for kv in r.attributes {
		if kv.key == key {
			return kv.value
		}
	}
	return none
}

// merge returns `r` with the attributes of `updating` added; where both have a
// key, `updating`'s value wins. Their schema URLs must agree, or one be empty.
pub fn (r Resource) merge(updating Resource) !Resource {
	schema_url := if r.schema_url == '' {
		updating.schema_url
	} else if updating.schema_url == '' || updating.schema_url == r.schema_url {
		r.schema_url
	} else {
		return error('resources with different schema URLs (`${r.schema_url}` and `${updating.schema_url}`) cannot be merged')
	}
	mut all := r.attributes.clone()
	all << updating.attributes
	return Resource{
		attributes: dedup(all)
		schema_url: schema_url
	}
}

// sdk returns the attributes that name this SDK: `telemetry.sdk.name`,
// `.language` and `.version`.
pub fn sdk() Resource {
	return Resource.new([
		otel.string_attr(semconv.telemetry_sdk_name, sdk_name),
		otel.string_attr(semconv.telemetry_sdk_language, sdk_language),
		otel.string_attr(semconv.telemetry_sdk_version, otel.version),
	], '')
}

// from_env returns the resource the environment describes:
// `OTEL_RESOURCE_ATTRIBUTES`, then `OTEL_SERVICE_NAME`, which wins over a
// `service.name` in the first. A malformed `OTEL_RESOURCE_ATTRIBUTES` is an
// error, and none of it is used, as the specification asks.
pub fn from_env() !Resource {
	mut attrs := parse_resource_attributes(os.getenv('OTEL_RESOURCE_ATTRIBUTES'))!
	service := os.getenv('OTEL_SERVICE_NAME').trim_space()
	if service != '' {
		attrs << otel.string_attr(semconv.service_name, service)
	}
	return Resource.new(attrs, '')
}

// default returns what every app's resource starts from: this SDK's attributes,
// `service.name` as `unknown_service:<executable>`, and the environment's
// attributes over them. An app merges its own over this, so they win over the
// environment's. A malformed environment is an error; `default_without_env` is
// the same resource without it, for an app that reports that and carries on.
pub fn default() !Resource {
	return default_without_env().merge(from_env()!)!
}

// default_without_env returns `default`'s resource without the environment's
// attributes.
pub fn default_without_env() Resource {
	executable := os.file_name(os.executable()).all_before_last('.exe')
	mut attrs := sdk().attributes
	attrs << otel.string_attr(semconv.service_name, 'unknown_service:${executable}')
	return Resource.new(attrs, '')
}

// parse_resource_attributes reads `key=value,key=value`, values
// percent-encoded, as `OTEL_RESOURCE_ATTRIBUTES` holds them. Space around keys
// and values is dropped. The error says which entry is wrong, but not its value.
fn parse_resource_attributes(s string) ![]otel.KeyValue {
	mut attrs := []otel.KeyValue{}
	if s.trim_space() == '' {
		return attrs
	}
	for i, entry in s.split(',') {
		eq := entry.index_u8(`=`)
		if eq < 0 {
			return error('OTEL_RESOURCE_ATTRIBUTES: entry ${i + 1} has no `=`')
		}
		key := entry[..eq].trim_space()
		if key == '' {
			return error('OTEL_RESOURCE_ATTRIBUTES: entry ${i + 1} has no key')
		}
		value := urllib.path_unescape(entry[eq + 1..].trim_space()) or {
			return error('OTEL_RESOURCE_ATTRIBUTES: the value of `${key}` has a bad percent-encoding')
		}
		attrs << otel.string_attr(key, value)
	}
	return attrs
}

// dedup keeps the last value of each key, drops empty keys, and sorts by key.
fn dedup(attributes []otel.KeyValue) []otel.KeyValue {
	mut last := map[string]int{}
	for i, kv in attributes {
		if kv.key != '' {
			last[kv.key] = i
		}
	}
	mut keys := last.keys()
	keys.sort()
	return keys.map(attributes[last[it]])
}

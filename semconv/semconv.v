// Package semconv names the attributes of the OpenTelemetry semantic
// conventions, so spans from different libraries describe the same things the
// same way.
module semconv

// service_name is the logical name of the service, such as `checkout`.
pub const service_name = 'service.name'

// service_version is the version of the service, such as `1.4.2`.
pub const service_version = 'service.version'

// telemetry_sdk_name is the name of the SDK that made the telemetry.
pub const telemetry_sdk_name = 'telemetry.sdk.name'

// telemetry_sdk_language is the language of the SDK that made the telemetry.
pub const telemetry_sdk_language = 'telemetry.sdk.language'

// telemetry_sdk_version is the version of the SDK that made the telemetry.
pub const telemetry_sdk_version = 'telemetry.sdk.version'

// exception_event is the name of the event a span records for an error.
pub const exception_event = 'exception'

// exception_type is the type of an error, such as `MessageError`.
pub const exception_type = 'exception.type'

// exception_message is an error's message. It can quote the values that
// failed, so the SDK records it only when asked.
pub const exception_message = 'exception.message'

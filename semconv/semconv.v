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

// http_request_method is the request's method, such as `GET`.
pub const http_request_method = 'http.request.method'

// http_route is the route a request matched, such as `/users/:id`: the path
// with its variable parts as names, so all its requests group together.
pub const http_route = 'http.route'

// http_response_status_code is the response's status code, such as `200`.
pub const http_response_status_code = 'http.response.status_code'

// url_path is the request's path, such as `/users/42`.
pub const url_path = 'url.path'

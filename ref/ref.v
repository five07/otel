// Package ref makes short, stable names for values that must not appear in
// telemetry: a keyed hash of the value's canonical JSON. Without the key a ref
// reveals nothing; with it, the ref can be made again from a known value and
// searched for.
module ref

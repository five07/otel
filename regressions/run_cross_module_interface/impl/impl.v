module impl

import api

// T implements `api.Tracer`.
pub struct T {}

// start returns its argument.
pub fn (t T) start(x int) int {
	return x
}

// tracer returns a `T` as an `api.Tracer`.
pub fn tracer() api.Tracer {
	return T{}
}

// A method of an interface from one module, called on a struct from another
// module, returns the wrong value under plain `v run` on V master: the program
// prints `0 0` where it should print `1 1`. With pointers in place of ints the
// result is a segfault. On a cold module cache the first `v run` can instead
// stop in the C compiler with `unknown type name 'sync__OnceLock_T'`.
// Only `v run`'s default build is wrong (cached modules linked as a dev dylib):
// `v -o x . && ./x`, `v test`, `v -nocache run .`, `v -prod run .` and
// `v -cc tcc run .` all print `1 1`.
// Run: `v run .` in this folder.
// Worked around: nothing in the library; its tests run under `v test`, and the
// examples are checked by their `main_test.v`. Run an example with
// `v -nocache run .` until this is fixed.
module main

import api
import impl

fn main() {
	cast := api.Tracer(impl.T{})
	returned := impl.tracer()
	println('${cast.start(1)} ${returned.start(1)}')
}

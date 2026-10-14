// Package ref makes short, stable names for values that must not appear in
// telemetry: a keyed hash of the value's canonical JSON. Without the key a ref
// reveals nothing; with it, the ref can be made again from a known value and
// searched for.
module ref

import crypto.hmac
import crypto.rand as crypto_rand
import crypto.sha256
import encoding.hex
import os
import five07.otel

// Mode is how refs are made.
pub enum Mode {
	// hmac is keyed: `hmac:<hex>`. Use it for anything that may hold personal
	// data; a plain hash of a guessable value (an email, an account number) can
	// be reversed by hashing guesses
	hmac
	// plain is unkeyed: `sha256:<hex>`, for an app that wants short stable
	// names and no key to manage
	plain
	// off makes no refs: the helpers return an empty string or none
	off
}

// min_key_bytes is the shortest key `hmac` mode takes.
pub const min_key_bytes = 32

// RefConfig sets up `Refs`.
@[params]
pub struct RefConfig {
pub:
	mode Mode = .hmac
	// length is the number of hex characters kept: 16 to 64, in steps of 8. 32
	// (128 bits) by default; 16 is fine for finding a ref, not for proving one
	length int = 32
	// key is the HMAC key; by default `OTEL_REF_KEY` (hex), else a random key
	// for this process alone
	key ?[]u8
}

// Refs makes refs. It never changes, and may be used from any thread.
pub struct Refs {
	mode   Mode
	length int
	key    []u8
}

// Refs.new returns refs as `config` sets. In `hmac` mode with no key given and
// no `OTEL_REF_KEY`, the key is random, so refs match only within this process;
// that is written to stderr. A length outside 16 to 64 in steps of 8, a key
// shorter than 32 bytes, or an `OTEL_REF_KEY` that isn't hex is an error: a
// random key in its place would quietly make refs no one can look up.
pub fn Refs.new(config RefConfig) !Refs {
	r, warnings := new_refs(config)!
	for w in warnings {
		eprintln('otel: ${w}')
	}
	return r
}

fn new_refs(config RefConfig) !(Refs, []string) {
	if config.length < 16 || config.length > 64 || config.length % 8 != 0 {
		return error('a ref length is 16 to 64 hex characters, in steps of 8, not ${config.length}')
	}
	mut warnings := []string{}
	mut key := []u8{}
	if config.mode == .hmac {
		if k := config.key {
			key = k.clone()
		} else {
			env := os.getenv('OTEL_REF_KEY').trim_space()
			if env != '' {
				key = hex.decode(env) or { return error('OTEL_REF_KEY: not hex') }
			} else {
				key = crypto_rand.bytes(min_key_bytes)!
				warnings << 'no OTEL_REF_KEY: hmac refs use a random key, and match only within this process'
			}
		}
		if key.len < min_key_bytes {
			return error('a ref key is at least ${min_key_bytes} bytes (${min_key_bytes * 2} hex characters), not ${key.len}')
		}
	}
	return Refs{
		mode:   config.mode
		length: config.length
		key:    key
	}, warnings
}

// ref names `v`: `hmac:<hex>` in `hmac` mode, `sha256:<hex>` in `plain` mode,
// and an empty string when `off`. Values that canonical JSON can't write (NaN,
// text that isn't UTF-8) are an error.
pub fn (r Refs) ref(v Value) !string {
	return match r.mode {
		.hmac { 'hmac:' + r.digest(v, true)! }
		.plain { r.plain(v)! }
		.off { '' }
	}
}

// plain names `v` without the key, `sha256:<hex>`, for values that aren't
// sensitive, such as a prompt's fixed prefix; an empty string when `off`.
pub fn (r Refs) plain(v Value) !string {
	if r.mode == .off {
		return ''
	}
	return 'sha256:' + r.digest(v, false)!
}

// attribute returns an attribute holding `v`'s ref, or none when refs are off
// or `v` can't be written as canonical JSON.
pub fn (r Refs) attribute(key string, v Value) ?otel.KeyValue {
	s := r.ref(v) or { return none }
	if s == '' {
		return none
	}
	return otel.string_attr(key, s)
}

// plain_attribute is `attribute` with `plain`.
pub fn (r Refs) plain_attribute(key string, v Value) ?otel.KeyValue {
	s := r.plain(v) or { return none }
	if s == '' {
		return none
	}
	return otel.string_attr(key, s)
}

fn (r Refs) digest(v Value, keyed bool) !string {
	text := canonical(v)!.bytes()
	sum := if keyed {
		hmac.new(r.key, text, sha256.sum, sha256.block_size)
	} else {
		sha256.sum(text)
	}
	return sum.hex()[..r.length]
}

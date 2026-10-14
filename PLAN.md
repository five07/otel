# otel: plan

## 0. Context for agents

**What this is.** An OpenTelemetry SDK for V, with no dependencies outside V's
standard library. Any V program can use it to emit telemetry that follows the
OpenTelemetry standards and lands in any OTLP collector. The long-term goal is the
feature set of the Go SDK (https://opentelemetry.io/docs/languages/go/); this plan
gets there in releases: traces in v0.1.0, metrics in v0.2.0, logs and events in
v0.3.0.

**Who uses it first.** vgraph (github.com/five07/vgraph, `~/Projects/vlang/vgraph`)
adds `five07.otel` as a dependency and does its own instrumentation: statement
spans, GraphQL request and resolver spans, and the db and graphql semantic
conventions. That work is planned and done in vgraph. This repo never imports
vgraph. Section 3 lists what vgraph needs from here.

**Second use: agent harnesses.** The user plans an experimental agent harness in V.
It needs long-running spans, keyed hashed refs (P4) that name a payload without
revealing it, and a payload channel separate from spans. GenAI semantic conventions
are left to the integrator for now (stretch, section 5).

**Hashed refs.** Taken from `~/Projects/python/harness-trace-lab`
(`harness/capabilities.py`, `payload_ref` and `pii_ref`): a span attribute holds
`hmac:` plus hex of HMAC-SHA256 over canonical JSON of a value. Without the key the
value can't be guessed; an engineer with the key can rebuild the ref from a known
input and find every span that touched it.

**How to work here.**
- **Never commit.** The user makes every commit.
- **Decisions go in this file**, as numbered **Q** with a **Default** and an empty
  `> A:` line the user fills in. Read the answers before starting a phase. Record
  each block's result under it in one or two lines, with anything decided along
  the way. Don't cite this file or its Q numbers from code, comments or docs: it is
  deleted before release.
- **Blocks.** Each phase is cut into blocks of about 30 minutes (`P1.3`). Do one
  block, run `v fmt -w`, `v vet -W` and `v -nocache test` on what it touched (see
  P2.4 for why `-nocache`), report, and stop.
  If a block turns out bigger, split it here before going on.
- **V:** the same V master as vgraph. Generics across modules and comptime are
  where compiler bugs have been; keep to plain structs, interfaces and sum types,
  and add a `regressions/` program for each new compiler bug.
- **No globals.** V needs `-enable-globals` for module-level mutable state, and a
  library must not force that on its users. There is no `otel.set_tracer_provider()`
  as in Go; the app builds a provider and hands it to what it instruments (Q2).
- **Style:** as vgraph: doc comments on every `pub` item (`v vet`), plain short
  sentences that say what a thing does and why.

## 1. Decisions already made

These came out of the first review (2026-10-14) and are not open:

- **No dependencies.** Standard library only. vgraph depends on otel, never the
  other way round.
- **Context carries the span.** `vlib/context` is the mechanism, as
  `context.Context` is in Go. vgraph moves its hooks example to `vlib/context` too
  (its own plan).
- **Layout** as Go: a light API module that libraries import, with no-op defaults,
  and an SDK the app wires up:
  - `five07.otel`: API: `TracerProvider`, `Tracer`, `Span` interfaces, `SpanContext`,
    attributes, status, span kinds, the context helpers, no-op implementations;
  - `five07.otel.sdk.trace`: the trace SDK: provider, spans, samplers,
    processors, ids. SDK modules are named for their signal, as in Go
    (`sdk/trace`, later `sdk/metric`, `sdk/log`), even where V's stdlib has a
    module of the same name; an app that wants both aliases one;
  - `five07.otel.sdk.resource`: `Resource` and its environment detector;
  - `five07.otel.propagation`: W3C `traceparent`, `tracestate`, `baggage`;
  - `five07.otel.ref`: hashed refs and the JSON canonicalizer;
  - `five07.otel.exporters.stdout` and `five07.otel.exporters.otlphttp`;
  - `five07.otel.semconv`: attribute name constants (only the general ones; db,
    graphql and gen_ai names belong to their integrators for now).
- **Export (v0.1.0):** OTLP/HTTP with JSON, POST `/v1/traces`; env vars
  `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`,
  `OTEL_EXPORTER_OTLP_HEADERS`, `OTEL_SERVICE_NAME`; a batch processor on its own
  thread fed by a channel (every 5 s or 512 spans, queue of 2,048 that drops and
  counts when full, `shutdown()` that flushes); one retry on 429/502/503/504; a
  stdout exporter (one JSON line per span). No gRPC or protobuf.
- **Propagation:** W3C Trace Context (version `00`, sampled flag, `tracestate`
  passed through) and W3C Baggage. No B3 or Jaeger headers.
- **Refs:** a canonicalizer is needed; the length is configurable; refs can be
  turned off by config.
- **Releases:** v0.1.0 traces (with span events and links), v0.2.0 metrics,
  v0.3.0 logs and events. GenAI conventions and the V harness are a stretch goal.
- **Bad environment variables** (the user's rule, 2026-10-14): when a bad or
  unknown value has a safe default, it is a warning on stderr (`otel: …`) and
  the default is used, as the specification asks: samplers, span limits,
  `OTEL_RESOURCE_ATTRIBUTES`, `OTEL_PROPAGATORS`. When falling back would cause
  harm, it is an error: a malformed `OTEL_REF_KEY` (a random key would quietly
  make refs no one can look up), and in P5 a malformed exporter endpoint (data
  sent somewhere else). Readers return their warnings as a list, so tests check
  them; only the public entry point prints.
- **Conventions from vgraph** (Q9; look at `~/Projects/vlang/vgraph` when in doubt):
  - **Branches:** work on `develop`, pull requests go to `develop`, `main` gets
    releases. CI runs on pushes to `main`.
  - **CI** (`.github/workflows/ci.yml`): Ubuntu 24.04, V built from a pinned
    `V_COMMIT` (bumped on purpose, with a comment saying why), the checkout linked
    to `~/.vmodules/five07/otel`, then `v fmt -verify`, `v vet` over the library
    modules, `v doc -f html -m` must build, `v test`. Jobs with outside tools
    (here: the OTLP collector check) are separate jobs.
  - **GitHub templates:** `pull_request_template.md` (what and why, and a
    checklist: tests, docs and snippets, fmt and vet, regressions) and
    `ISSUE_TEMPLATE/` (bug report, docs, feature request, `config.yml`).
  - **Docs:** `README.md` (what it is, status with the V commit, a quick start,
    links), `docs/README.md` as a numbered index of guides, one guide per topic.
    Every ```v block in the README and guides is preceded by
    `<!-- snippet: <path>#<name> -->` and must equal the region between
    `// snippet: <name>` and `// end snippet` in a file under `docs/snippets`, a
    project that compiles and runs in its tests; `docs/snippets/docs_test.v`
    checks this, and `UPDATE_SNIPPETS=1` rewrites the blocks.
  - **Examples:** `examples/<name>/` each with its own `v.mod`, `README.md` (what
    it shows, how to run it), `main.v` and `main_test.v`; `examples/setup.vsh`
    links the checkout into `~/.vmodules` as `five07.otel` or says which one V
    will use.
  - **`.vdocignore`:** `examples/`, `docs/`, `regressions/`, so `v doc` covers the
    library alone.

## 2. Questions

All answered on 2026-10-14, every default taken. New questions go here as Q10 on.

**Q1. Context key.** `context.Key` is a sum type of primitives, so a package can't
define its own key type as Go advises. **Default:** the key is the `voidptr` of a
private module-level constant, which no other package can produce; a string key
(`'five07.otel.span'`) is the fallback if V won't take a const's address in a
`Key`. The helpers: `otel.context_with_span(ctx, span) context.Context`,
`otel.span_from_context(ctx) Span` (a no-op span when none is set, so callers never
unwrap), and the same pair for baggage.
> A: agreed

**Q2. Providers without globals.** **Default:** libraries take an
`otel.TracerProvider` (interface) in their config, defaulting to
`otel.noop_tracer_provider()`, and get a tracer with
`provider.tracer('name', version: '1.2.0')`. The app builds one
`sdk.trace.TracerProvider` at startup and passes it on. Alternative: an opt-in
global behind `$if otel_globals ?` for apps that build with `-enable-globals`.
Not in v0.1.0 unless asked.
> A: agreed

**Q3. Ref format and length.** **Default:** `<alg>:<hex>`, with `alg` one of `hmac`
(keyed, for anything that may hold PII) and `sha256` (plain, for values that are
not sensitive, such as a prompt prefix). Length in hex characters, default 32 (128
bits), allowed 16 to 64 in steps of 8; 64 is the whole digest. 16 matches
harness-trace-lab and is fine for lookup, not for proving integrity; the docs say
so.
> A: agreed

**Q4. Ref modes.** **Default:** `RefConfig.mode` is one of `.hmac` (default),
`.plain` (all refs are unkeyed `sha256:`, for users who don't want opaque refs but
still want short stable names), and `.off` (ref helpers return an empty string and
the attribute is left out). The key comes from `OTEL_REF_KEY` (hex or base64?) or
the config; with neither, a random key per process and one warning on stderr,
since refs then join only within a process. A key id can be added later
(`hmac:k1:…`) for rotation; not in v0.1.0.
> A: agreed
Key format, left open by the answer: hex, at least 32 bytes (64 hex characters),
since `openssl rand -hex 32` makes one; a shorter or non-hex key is an error.

**Q5. Canonical JSON.** harness-trace-lab uses Python's `json.dumps(sort_keys=True,
separators=(",", ":"))`. That differs from RFC 8785 (JCS) in two places: it escapes
non-ASCII as `\uXXXX` where JCS writes UTF-8, and it prints floats with Python's
`repr` where JCS uses the ECMAScript form (`1e+21`, `1.5e-7`). **Default:** JCS,
since it is a standard other languages can match, and change harness-trace-lab to
JCS (a small change there) so refs agree across both. Refs over ASCII strings,
ints, bools, null, lists and maps already agree. Input is a `ref.Value` sum type
(string, i64, f64, bool, null, list, map), plus a helper from `json2.Any`.
> A: agreed -> JCS

**Q6. Events naming.** "Events" in v0.3.0: the OpenTelemetry Events signal (log
records with an event name), not span events. **Default:** span events
(`span.add_event(name, attrs)`, and `record_error`) are in v0.1.0, since status and
errors need them and they are part of the trace signal; the Events/Logs signal is
v0.3.0.
> A: agreed

**Q7. Sampler and ids.** **Default:** samplers AlwaysOn, AlwaysOff,
TraceIdRatioBased (the spec's algorithm, on the trace id, so V decides as other
SDKs do) and ParentBased (wrapping one of these), set by
`OTEL_TRACES_SAMPLER` and `OTEL_TRACES_SAMPLER_ARG` too. Ids from a fast generator
seeded once from `crypto.rand`, not a syscall per id; a test may give its own
generator.
> A: agreed

**Q8. Error messages.** vgraph never puts error messages in spans, since they can
quote values. The SDK can't know what's safe. **Default:** `record_error(err)` adds
an `exception` event with `exception.type` only; `exception.message` only when the
caller passes `with_message: true`. Status descriptions are left to the caller.
> A: agreed

**Q9. Repository conventions.** Raised by the user: follow vgraph's conventions
for docs, examples and GitHub workflows. Recorded in section 1 ("Conventions from
vgraph") and in blocks P0.1, P0.3, P6.
> A: one additional item: utilize the conventions in the `five07/vgraph` package for docs, examples and github workflows

## 3. What vgraph needs from otel (its contract)

vgraph's plan owns the work; this section lists only what it relies on, so the API
here doesn't drift from it. Keep it short and current.

- `otel.TracerProvider`, `Tracer.start(ctx, name, opts) (context.Context, Span)`,
  `Span.end()`, `set_attribute`, `set_status`, `add_event`, `record_error`, span
  kinds server, client and internal;
- a way to start a span with an explicit start time (statement spans start where
  the statement did); such a time has the wall clock's resolution (a
  microsecond on macOS), so it can sit up to that much before its parent's
  start (P2.7);
- `otel.span_from_context` and `otel.context_with_span` (Q1);
- `propagation.TraceContext.extract(headers) context.Context` from a map or a
  getter fn, since vgraph's `HttpRequest` has no headers and the app reads them
  from its framework;
- no-op defaults costing nothing measurable, so vgraph can always call the API.

## 4. Phases to v0.1.0

Order: P0 → P1 → P2 → P3 → P4 → P5 → P6 → P7. P4 (refs) depends only on P0 and
can be done any time after it.

### P0. Scaffold

- **P0.1** `v.mod` (`five07.otel`, version `0.0.0`, no dependencies, the same
  fields as vgraph's), the module directories from section 1 with one
  doc-commented file each, `.gitignore`, `.vdocignore`, `LICENSE` (MIT, as
  vgraph), a stub README in vgraph's shape. `v test .` runs (empty). The user
  creates `develop`.
  *Done.* Also copied vgraph's `.editorconfig` and `.gitattributes`. fmt, vet,
  test (0 files) and `v doc -m` (8 modules) pass. V's stdlib has its own `trace`
  module (`vlib/trace`, a timing profiler). Renamed to `sdk/sdktrace` for it in
  P0.2, then back to `sdk/trace` by the user's call: it isn't a concern, and an
  app that imports both aliases one (section 1, layout).
- **P0.2** Check that V handles the layout: a test program in `regressions/` that
  imports `five07.otel` and `five07.otel.sdk.trace` through a local module path,
  with an interface in one and its implementation in the other. Record what works.
  *Done.* Probed in a scratch copy: the API module with `Span`, `Tracer` and
  `TracerProvider` interfaces and a span in a `context.Context`, the SDK
  module implementing them, and an app importing both beside vlib's `trace`. The layout
  works: `v build`, `v test`, `-prod`, `-nocache` and `-cc tcc` all give the right
  results (the probe used the name `sdktrace` beside vlib's `trace`).
  - Imports of `five07.otel` from inside the repo (the SDK's own tests too)
    need the checkout linked into `VMODULES`, so P0.5's `setup.vsh` comes before
    P2's first test, and CI links it as vgraph's does.
  - V bug: plain `v run` (cached modules linked as a dev dylib) miscompiles a
    call through an interface from one module on a struct from another: wrong
    values, a segfault with pointers, or on a cold cache a C error
    `unknown type name 'sync__OnceLock_T'`. Program:
    `regressions/run_cross_module_interface` (prints `0 0`, should be `1 1`).
    No workaround in the library; examples are checked with `v test`, and their
    READMEs say `v -nocache run .` until it's fixed. Worth reporting upstream.
- **P0.3** CI as vgraph's (section 1): `ci.yml` with the pinned `V_COMMIT`,
  fmt, vet, `v doc`, test.
  *Done* (after P0.5, which it needs). One job: build V at `V_COMMIT`, `v run
  otel/examples/setup.vsh`, fmt, vet, `v doc`, test. Every step passes run
  locally from the parent folder with a scratch `VMODULES`. On push to `main`
  only, as vgraph; nothing checks `develop` until a merge.
  - `v vet` only warns about a missing doc comment and exits 0, so it can't fail
    a job; here it runs with `-W`. vgraph's CI runs it without, so its doc check
    has never failed a build (for vgraph's plan).
  - `v vet` looks back from a function to the first `}` for a comment, so the
    first function of a file, before any `}`, takes the module's doc comment as
    its own and isn't checked. Review that one by eye. It checks functions only,
    not structs, interfaces or consts.
- **P0.4** GitHub templates copied from vgraph and adapted: the pull request
  checklist (no generated code or PostgreSQL items; add "the OTLP JSON tests
  pass"), the issue forms.
  *Done.* PR checklist: tests (with `setup.vsh` and the OTLP golden files), a
  telemetry item (nothing reaches a span the caller didn't put there), docs and
  snippets, fmt and `vet -W`, regressions. Bug form asks for the provider and
  recording code, what was exported (values scrubbed), V and otel versions, the
  exporter, the collector; it points at `v -nocache run .` for the `v run` bug.
  Feature form asks for the spec section or Go SDK feature in place of Ent's.
  `config.yml` adds a link to the specification. The labels the forms use
  (`bug`, `docs`, `feature request`, and `upstream`) must exist on GitHub.
- **P0.5** `examples/setup.vsh` (vgraph's, for `five07.otel`) and the
  `docs/snippets` project with its `docs_test.v`, ported from vgraph and passing
  with no snippets yet.
  *Done.* `setup.vsh` is vgraph's with the names changed; tried on a scratch
  `VMODULES`: links, says so on a second run, and refuses (exit 1) when another
  `five07.otel` is installed. `docs_test.v` is vgraph's without its last check
  that at least one block was checked, which fails with no guides; put
  `assert checked > 0` back in P6.4 with the first guide. The user runs
  `v run examples/setup.vsh` once (not run on `~/.vmodules` here).

### P1. API module (`five07.otel`)

- **P1.1** `TraceId` (16 bytes) and `SpanId` (8 bytes): hex encode and decode,
  `is_valid()` (not all zero), tests.
  *Done* (`ids.v`, `ids_test.v`). Structs over a fixed array (`bytes [16]u8`,
  public, read-only), so the id generator builds them directly and `==` compares
  by value. `TraceId.from_hex` / `SpanId.from_hex` (the static constructor style
  vgraph uses), `hex()`, `str()` (the hex, for interpolation), `is_valid()`. As
  in Go: lowercase hex only, and the all-zero id is an error from `from_hex`.
  Errors give the expected length or "lowercase hex only", never the input,
  which comes from a header. Tests use the W3C spec's example ids; a mutation
  (accepting upper case) makes them fail.
- **P1.2** `TraceFlags` (sampled bit), `TraceState` (an ordered list of key-value
  pairs, kept as-is, with the spec's limits: 32 entries, key and value grammar),
  `SpanContext` (ids, flags, state, `remote`), tests.
  *Done* (`span_context.v`, `trace_state.v`, tests). `TraceFlags{bits}` with
  `is_sampled`, `with_sampled` (other bits kept, for later spec versions),
  `hex`. `TraceState` never changes, as Go's: `insert` (checks the W3C key and
  value grammar, moves the entry first, drops the last when a new one passes 32),
  `delete`, `get ?string`, `len`, `members` (a copy), `str` (the header form).
  Parsing the header stays in P3.3. `SpanContext` has public read-only fields,
  `is_valid` (both ids), `is_sampled`; `==` compares by value, state included.
  `v vet` prints notices (`== ''` over `.len == 0`) that `-W` doesn't fail on;
  fix them anyway.
- **P1.3** Attributes: `Value` sum type (string, bool, i64, f64, and arrays of
  each), `KeyValue`, helpers `otel.string('k', 'v')` and so on; tests.
  *Done* (`attribute.v`, tests). `Value = string | bool | i64 | f64 | []string |
  []bool | []i64 | []f64`; `KeyValue{key, value}`. Helpers are suffixed, by the
  user's choice (2026-10-14): `string_attr`, `bool_attr`, `int_attr` (to i64),
  `i64_attr`, `f64_attr`, and the lists `strings_attr`, `bools_attr`,
  `ints_attr`, `i64s_attr`, `f64s_attr`, which keep a copy. V does accept
  `otel.string(...)`, but a function named after a built-in type may not last.
  No `attr(key, Value)` taking anything: an untyped `3` passed to a sum type
  without `int` reaches the C compiler (`regressions/int_literal_to_sum_type.vv`).
  Empty keys are the SDK's to drop (P2.3).
- **P1.4** `SpanKind`, `StatusCode` (unset, ok, error), `Status`, `SpanStartOptions`
  (kind, attributes, links, start time, new root), `EndOptions` (end time).
  *Done* (`span.v`, `span_test.v`). `SpanKind` with `internal` first, so it is
  the zero value; `StatusCode` unset, ok, error, in OTLP's order (0, 1, 2), which
  a test pins; `Status{code, description}`; `Link{span_context, attributes}`.
  The options are `@[params]` structs, so calls read `start(ctx, 'name', kind:
  .server)`; the times are `?time.Time`, none meaning now. The rules (an ok
  status sticks, a description only with an error) belong to the SDK (P2.7).
  `SpanKind` numbers differ from OTLP's (internal is 1 there): P5.2 maps them.
- **P1.5** `Span`, `Tracer` and `TracerProvider` interfaces, and their no-op
  versions; tests that a no-op span from a context carrying a remote span context
  keeps that context (as Go does, so propagation works without an SDK).
  *Done* (`span.v`, `tracer.v`, `noop.v`, `noop_test.v`), but the "keeps the
  remote context" part moves to P1.6, which has the context helpers it needs;
  until then `NoopTracer.start` returns `ctx` as is and an empty `NoopSpan`.
  - `Span`'s methods aren't `mut`, so callers write `ctx, span := t.start(...)`,
    not `mut span`. The SDK keeps a span's data in a `shared` field and locks it
    (probed: 8 threads × 1,000 `set_attributes` on one span keep all 8,000, and
    calls after `end` are ignored).
  - `Span`: `span_context`, `is_recording`, `set_name`, `set_attributes(...KeyValue)`,
    `add_event(name, EventOptions)`, `add_link`, `set_status(Status)`,
    `record_error(IError, ErrorOptions)` (`with_message` per Q8), `end(EndOptions)`.
    `Status` is `@[params]` too: `span.set_status(code: .error)`.
  - `Tracer.start(ctx, name, SpanStartOptions) (context.Context, Span)`;
    `TracerProvider.tracer(name, TracerOptions)` (version, schema URL,
    attributes); `noop_tracer_provider()` and public `Noop*` structs.
  - Checked from another module through the `VMODULES` link under `v test`: the
    no-op API, and a library's own span and tracer types.
  - A struct named `T` makes V master write broken C (`sync__ThreadLocalStorage_T`);
    V reserves single capitals for generics, so don't use one.
- **P1.6** Context helpers (Q1): span in and out of `context.Context`; tests with
  `context.background()` and nested values. `NoopTracer.start` then takes the
  parent's span context into its `NoopSpan`, with the test moved from P1.5.
  *Done* (`context.v`, `context_test.v`, `noop.v`). The key is Q1's default: the
  address of a private const (`voidptr(&span_key_cell)`), which V takes; each
  key's cell will hold its own value so no compiler can merge two. A string key
  can't find the span (tested). `context_with_span`, `span_from_context` (a
  `NoopSpan` when none), and `context_with_span_context` for a parent read from
  a header (P3.3 uses it). `NoopTracer.start` now carries the parent's span
  context (none with `new_root`) and puts its span in the context, so a trace
  passes through code that records nothing. Tests pass under `-prod` too, and
  from another module. Baggage's pair of helpers comes with `Baggage` in P3.4.
  Each `_test.v` compiles alone, so a test helper type (P1.5's `Recorder`) can't
  be shared between test files; the SDK's in-memory exporter (P2.6) will be the
  shared tool.

### P2. Trace SDK (`five07.otel.sdk.trace`)

- **P2.1** Id generator (Q7): seeded from `crypto.rand`, safe across threads;
  a deterministic one for tests.
  *Done* (`sdk/trace/id_generator.v`, tests). `IdGenerator` interface
  (`new_trace_id`, `new_span_id`, any thread, never all zero).
  `RandomIdGenerator.new() !`: xoroshiro128++ (128-bit state, so a full trace id
  isn't drawn from 64 bits of state) seeded once from `crypto.rand`, behind a
  `shared` lock; `RandomIdGenerator.with_seed([4]u32)` repeats its ids.
  `SequentialIdGenerator` counts trace and span ids from 1, so tests (and the
  OTLP golden files, P5.2) know their ids. Tested: 1,000 ids unique and valid, 8
  threads × 2,000 span ids unique, seeds repeat, big-endian byte order; also
  under `-prod`. macOS `sed` lacks GNU's `0,/re/`: mutation checks use Python.
- **P2.2** `Resource` in `sdk.resource`: attributes, merge,
  `telemetry.sdk.name/language/version`, `service.name` from `OTEL_SERVICE_NAME`,
  `OTEL_RESOURCE_ATTRIBUTES` parsing; tests.
  *Done* (`sdk/resource/resource.v`, tests; `otel.version`; first `semconv`
  constants). `Resource.new(attrs, schema_url)` (last value of a key wins, empty
  keys dropped, sorted by key), `attributes()` (a copy), `get`, `merge` (the
  updating resource wins; schema URLs must agree or one be empty, else an error).
  `sdk()`: `telemetry.sdk.name` `five07.otel` (the spec asks an SDK that isn't
  the project's to name itself), `.language` `v`, `.version` `otel.version`,
  which a test keeps equal to `v.mod`'s (the user's call: two values and the
  test, which CI runs as its first check, right after building V). `from_env() !`: `OTEL_RESOURCE_ATTRIBUTES`
  (percent-decoded, `+` kept), then `OTEL_SERVICE_NAME` over its `service.name`;
  a malformed variable is an error and none of it is used. `default() !` = SDK
  attributes + `unknown_service:<executable>` + the environment;
  `default_without_env()` for an app that reports the error and goes on. Order:
  SDK < environment < the app's own (merged last). Errors name the entry, never
  its value.
- **P2.3** `RecordingSpan`: holds name, kind, context, parent, times (unix ns),
  attributes, events, links, status; setters guarded by a mutex and ignored after
  `end()`; attribute and event limits (128 each, as the spec defaults) with
  dropped counts.
  *Done* (`sdk/trace/span.v`, `span_test.v`; `exception.*` in `semconv`). Also
  took P2.7's status rules and `record_error`, since the span must implement all
  of `otel.Span`.
  - `RecordingSpan` keeps its changing data in `shared SpanState`; every method
    takes the lock and does nothing once ended. `end` runs once and hands a
    `ReadOnlySpan` (a copy that never changes) to the `on_end` callback, which
    P2.4's tracer points at the processors.
  - `ReadOnlySpan`: name, span context, parent, kind, start and end unix ns,
    attributes, events, links, their dropped counts, status, scope, resource.
    `Event` and `Link` (the SDK's, with dropped counts); `InstrumentationScope`.
  - `SpanLimits` (attributes, events, links 128; per event and per link 128).
    A key already set is replaced, a new key past the limit counted; empty keys
    are dropped uncounted; a link to an invalid context is ignored.
  - Status: `unset` ignored, `ok` final, a description only with `error`.
    `record_error`: an `exception` event with `exception.type`
    (`err.type_name()`), the message only with `with_message`; status untouched.
  - Times: given start or end used as is; otherwise the end is the start plus
    the monotonic clock's elapsed time (`time.sys_mono_now`), as Go does.
    macOS's wall clock has microsecond resolution.
  - Not yet: the `OTEL_SPAN_*_LIMIT` environment variables (P2.4, with the
    provider's settings), and the attribute value length limit (unlimited by
    default in the spec; later if asked).
- **P2.4** `TracerProvider` and `Tracer`: `start` picks the parent from the context
  (or a new root), asks the sampler, makes a recording or a non-recording span;
  instrumentation scope (name, version) on each span; span limits from
  `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT`, `OTEL_SPAN_EVENT_COUNT_LIMIT`,
  `OTEL_SPAN_LINK_COUNT_LIMIT`, `OTEL_EVENT_ATTRIBUTE_COUNT_LIMIT`,
  `OTEL_LINK_ATTRIBUTE_COUNT_LIMIT`.
  *Done* (`sdk/trace/provider.v`, `sampler.v`, `processor.v`, `provider_test.v`).
  - `TracerProvider.new(ProviderOptions) !`: resource (default
    `resource.default()`), sampler (default `AlwaysOnSampler` until P2.5 sets
    ParentBased), id generator (default `RandomIdGenerator`), processors,
    limits (default from the environment). Fails on a malformed environment, as
    `resource.default()` does, rather than warn and go on.
  - `Tracer.start`: the parent from the context unless `new_root`; a child keeps
    its parent's trace id and flags; the sampler's decision sets the sampled bit,
    its attributes join the span's, its trace state is the span's. `drop` gives a
    `NoopSpan` with real ids (the trace still propagates) and no processor calls;
    `record_only` records without the sampled bit. Processors' `on_start` see
    each recording span; `end` hands it to every `on_end`.
  - `Sampler` interface, `SamplingParameters` (the parent's span context, not a
    `context.Context`), `SamplingResult`, `SamplingDecision`; only
    `AlwaysOnSampler` so far. `SpanProcessor` interface (`on_start`, `on_end`,
    `force_flush !`, `shutdown !`), implemented in P2.6.
  - Limits from `OTEL_SPAN_ATTRIBUTE_COUNT_LIMIT` (else
    `OTEL_ATTRIBUTE_COUNT_LIMIT`) and the four others; a value that isn't a whole
    number from 0 is an error naming the variable.
  - Tested in-module (ids from `SequentialIdGenerator`), under `-prod`, and from
    another project as an app wiring the SDK into a library that takes
    `otel.TracerProvider`. Three mutations (child gets a new trace, drop records,
    sampled bit ignored) fail the tests.
  - **V bug: `v test` with the module cache.** Testing the whole repository (or
    `v test sdk`) hangs every time: after `resource`'s own tests run in a
    session, a later `trace` test spins forever in `sync.RwMutex.lazy_init`, on
    an `inited` value nothing writes, as if built against another layout of the
    struct; with `VJOBS=4` a test fails instead. Each directory alone passes, and
    so does everything with `-nocache` (3 s, faster than with the cache). A
    small two-module copy of the pattern did not hang, so there is no
    `regressions/` program yet; the repro is `v test sdk` at this commit. Worked
    around: `v -nocache test` in CI, the PR checklist and the README. Report it
    upstream with the `v run` one (P0.2).
- **P2.5** Samplers (Q7): AlwaysOn, AlwaysOff, TraceIdRatioBased, ParentBased;
  env vars; tests with the decisions carried to children.
  *Done* (`sdk/trace/sampler.v`, `sampler_test.v`; provider default now
  `sampler_from_env()`).
  - `always_on_sampler()`, `always_off_sampler()`, `trace_id_ratio_based(r)`,
    `parent_based(root, ParentBasedOptions)` (the four delegates default to on
    for a sampled parent, off for an unsampled one). Every sampler passes the
    parent's trace state on, kept or dropped.
  - The ratio test is Go's: the trace id's last 8 bytes, big-endian, shifted
    right one, below `ratio × 2⁶³`, so V and Go services keep the same traces.
    As in Go, a ratio of 1 or more is `AlwaysOnSampler`, below 0 is 0, and the
    descriptions match Go's (`TraceIDRatioBased{0.25}`, `ParentBased{root:…,
    remoteParentSampled:…,…}`; whole ratios print without `.0`).
  - `OTEL_TRACES_SAMPLER`: `always_on`, `always_off`, `traceidratio`, and each
    with `parentbased_`; unset is `parentbased_always_on`. `OTEL_TRACES_SAMPLER_ARG`
    is the ratio (1 if unset). An unknown name (`jaeger_remote`, `xray`) or a
    ratio outside 0 to 1 is an error, as with the other variables.
  - Tested: the byte boundaries of the ratio test, its ends, ~25% and ~50% of
    20,000 seeded ids with every 0.25-kept trace kept at 0.5, each parent case,
    descriptions, the environment, and the default provider dropping the
    children of an unsampled remote parent. Four mutations fail the tests; the
    remote/local swap needed its own test, since the defaults treat both alike.
- **P2.6** `SpanProcessor` interface (`on_start`, `on_end`, `force_flush`,
  `shutdown`), `SimpleSpanProcessor`, an in-memory exporter for tests;
  `provider.shutdown()` and `force_flush()` reach every processor.
  *Done* (`sdk/trace/exporter.v`, `simple_processor.v`, provider changes, tests).
  - `SpanExporter` (`export([]ReadOnlySpan) !`, `shutdown !`) lives here, as in
    Go, since processors need it; P5.1 implements stdout against it.
    `InMemoryExporter` (`spans()`, `reset()`, refuses exports after `shutdown`),
    public so an app's own tests can read back its spans.
  - `SimpleSpanProcessor.new(exporter, on_error: …)`: exports each sampled span
    as it ends, in the ending thread, under a lock so exports never overlap;
    unsampled (`record_only`) spans are skipped; after shutdown, nothing.
    `on_end` can't return an error, and there are no globals for Go's error
    handler, so errors go to `on_error`, by default one stderr line.
  - Provider `force_flush() !` and `shutdown() !` reach every processor in
    order; errors are joined with `; `. `shutdown` runs once, later calls do
    nothing; after it, tracers start spans that record nothing but keep valid
    ids, and a span ended after it isn't exported.
  - Tests: export order, unsampled and dropped spans skipped, `on_error`,
    shutdown once (counted at the provider, since the simple processor is
    idempotent on its own), late spans, flush errors, 8 threads × 250 spans all
    exported with distinct ids; `-prod` too. Three mutations fail the tests.
- **P2.7** Tests through the provider: parenting across three levels, sampled
  and not, ids and parents as exported, end times. (`record_error`, events,
  links and the status rules were done with P2.3.)
  *Done* (`sdk/trace/trace_test.v`, and a fix in `span.v` / `provider.v`). The
  SDK wired as an app wires it (parent-based sampler, simple processor,
  in-memory exporter, sequential ids): request → resolver → statement with ids,
  parents, kinds, scope and resource as exported; siblings; a sampled remote
  parent continuing its trace (the root sampler not asked); an unsampled one
  followed, nothing exported, but every level carrying the trace id and state
  for outgoing calls; a 0.5 ratio keeping ~half of 200 traces, each whole; a
  no-op library in the middle (the statement's parent is the request).
  - **Bug found and fixed:** a child could end after its parent in the export.
    Starts came from the wall clock (microseconds on macOS) and ends added the
    monotonic elapsed time, so a child starting just past a microsecond edge
    ended up to 1µs late. Now, as Java's SDK does, a trace's first span in the
    process takes an `Anchor` (one reading of both clocks) and its local
    children share it; every time is `anchor wall + monotonic elapsed`, one
    nanosecond timeline per trace, drift bounded by the trace's length. Events
    use it too. Without sharing, the nesting test fails 15 of 15 runs; with it,
    40 of 40 pass.
  - Times given explicitly (`start:`, `end:`, an event's `timestamp`) are used
    as given, as in Go, so they carry the wall clock's resolution: one taken
    with `time.now()` in the same microsecond as its parent's start can land up
    to 1µs before it. vgraph's statement spans should know (section 3).
  - Every SDK test file run 10× (40× for this one) without a failure; a
    mutation (spans exported without their parent) fails it.

### P3. Propagation (`five07.otel.propagation`)

- **P3.1** `TextMapCarrier` interface (`get`, `set`, `keys`) and a map carrier;
  `TextMapPropagator` interface (`inject`, `extract`, `fields`).
- **P3.2** `traceparent` parse and format, with the spec's test vectors: bad
  version, version `ff`, all-zero ids, wrong lengths, upper-case hex, future
  versions with extra fields.
- **P3.3** `tracestate` parse and format; `TraceContext` propagator putting both
  together; extract gives a context carrying a remote span context.
- **P3.4** `Baggage` (API types in `five07.otel`, members with properties,
  percent-encoding, the spec's size limits), in and out of the context, and its
  propagator.
- **P3.5** Composite propagator; `OTEL_PROPAGATORS` (`tracecontext,baggage`, the
  default; unknown names warn and are skipped).

*P3 done in one pass* (2026-10-14, at the user's request; `propagation/*.v`,
`baggage.v`, `TraceState.parse` in `trace_state.v`, baggage helpers in
`context.v`, tests). Parsing lives in the API, as in Go's `trace` and `baggage`
packages; `propagation` only reads and writes headers.
- P3.1: `TextMapCarrier` (`get ?string`, `keys`, `mut set`) and
  `TextMapPropagator` (`inject(ctx, mut carrier)`, `extract(ctx, carrier)
  context.Context`, `fields`). `MapCarrier.new(headers)` lowercases keys (HTTP
  names are case-insensitive), `to_map()` for an outgoing request.
  `GetterCarrier{get_fn}` for a framework with its own header type (section 3's
  "getter fn"); extract only.
- P3.2: `parse_traceparent` per the W3C: lowercase hex, `ff` invalid, version
  `00` exactly 55 characters, a later version may carry more after a `-`,
  all-zero ids invalid, spaces and tabs trimmed. Only the sampled flag is kept
  in and out, as Go does. Tested with the W3C cases (5 valid, 14 invalid).
- P3.3: `TraceState.parse` (spaces and empty entries allowed; a bad key or
  value, a duplicate key, or more than 32 entries is an error). `TraceContext`:
  extract gives a remote span context via `context_with_span_context`; a bad
  `traceparent` leaves the context as it is, a bad `tracestate` is dropped
  alone; inject writes nothing without a valid span, and no `tracestate` when
  empty. A service round trip (extract, no-op span, inject) keeps the trace.
- P3.4: `otel.Baggage` (never changes; `parse`, `get`, `member`, `set` with
  properties, `delete`, `len`, `members`, `str`), `BaggageMember`,
  `BaggageProperty{key, value ?string}`; keys are HTTP tokens; values are any
  text, percent-encoded out (every non-baggage octet, and `%`) and decoded in;
  at most 64 entries and 8,192 bytes, else the header is dropped; a repeated
  key keeps its last value; errors never quote values. `context_with_baggage`,
  `baggage_from_context` (key cell value 2). `BaggagePropagator`.
- P3.5: `composite(...)` (fields deduplicated), `default_propagator()`
  (tracecontext + baggage), `from_env()`: `OTEL_PROPAGATORS`, `none` for none;
  an unknown name (`b3`, `jaeger`) is skipped with a stderr warning, as the plan
  and the specification say. That differs from the samplers, limits and
  resource, where a bad variable is an error; the user may want one rule.
- Seven mutations (each a spec rule: version-00 length, `ff`, tracestate
  dropping the trace, `%` unencoded, composite chaining, flag masking,
  duplicate tracestate keys) each fail the tests; `-prod` passes.

### P4. Hashed refs (`five07.otel.ref`)

- **P4.1** `ref.Value` sum type and conversion from `json2.Any` (Q5).
- **P4.2** JCS canonicalizer: key sorting by UTF-16 code units, string escaping,
  integers. Tests from RFC 8785's examples.
- **P4.3** JCS numbers: the ECMAScript shortest-form float formatting, NaN and
  infinity rejected. Tests from RFC 8785's number vectors. (This is the hard
  block; split it if V's float printing doesn't give the shortest round-trip form.)
- **P4.4** `RefConfig` (Q3, Q4): mode, length, key from env or config, the
  per-process random key and its warning; `Refs.ref(v)`, `Refs.plain(v)`.
- **P4.5** Attribute helper: `refs.attribute('tool.args_ref', v) ?KeyValue`
  (none when mode is `.off`); cross-language vectors: a JSON file of inputs, key
  and expected refs, checked here and by a small script in harness-trace-lab.

*Environment warnings* (2026-10-14, before P4; section 1's rule). Samplers,
limits and `OTEL_RESOURCE_ATTRIBUTES` went from errors to warnings with
defaults: `sampler_from_env`, `limits_from_env` and `env_resource` return
`(value, []string)`; `resource.default()` and `from_env()` no longer return
`!` and `default_without_env` is gone; `TracerProvider.new` fails only without
a secure seed. A bad `OTEL_RESOURCE_ATTRIBUTES` still keeps
`OTEL_SERVICE_NAME`. Tests check the exact warnings.

*P4 done in one pass* (2026-10-14, at the user's request; `ref/value.v`,
`jcs.v`, `ref.v`, tests, `ref/testdata/`).
- P4.1: `ref.Value = Null | bool | int | i64 | f64 | string | []Value |
  map[string]Value`; `int` is there so `refs.ref(42)` works (the int-literal
  bug, P1.3). `from_json(json2.Any) !Value` (numbers as JSON's floats; a time is
  an error). V's `x.json2` is now an alias of `json2`.
- P4.2–4.3: `canonical(v) !string`, RFC 8785: keys sorted by UTF-16 code units,
  strings escaped as `JSON.stringify`, numbers by JavaScript's rules from Ryu's
  shortest digits (`strconv.ftoa_64`), which needed no split. `i64` is written
  exactly (beyond 2⁵³ a JavaScript JCS would round; documented). Tested with all
  of RFC 8785's number vectors (bit patterns), its key-order example (U+1F600
  before U+FB33), its full example document, escapes, and non-UTF-8 refused.
- P4.4: `Refs.new(RefConfig{mode, length, key}) !`: `.hmac` (default,
  `hmac:<hex>`), `.plain` (`sha256:<hex>`), `.off` (`''` / none). Length 16 to
  64 in steps of 8, default 32. Key from config, else `OTEL_REF_KEY` (hex, at
  least 32 bytes), else random with one warning; a malformed or short key is an
  error (section 1). `ref(v)`, `plain(v)` (unkeyed even in hmac mode).
- P4.5: `attribute(key, v) ?otel.KeyValue` and `plain_attribute`, none when off
  or unwritable (NaN). `ref/testdata/check_vectors.py` makes `vectors.json` (90
  cases: 15 ASCII inputs × hmac/plain × 16/32/64) the way harness-trace-lab
  makes refs; V's refs match all 90. It is not run in harness-trace-lab: that
  repository wasn't changed. On these inputs Python's `json.dumps(sort_keys)` is
  JCS; it differs for non-ASCII text and exponent floats (Q5), which is when
  harness-trace-lab would need its JCS change.
- Added after, at the user's request: `from_struct[T](v) !Value`, through
  `json2.encode` and `decode`, so `@[json]` names and `@[skip]` apply, a
  `time.Time` is its ISO-8601 string, and numbers are JSON's floats (an integer
  beyond 2⁵³ is rounded, as JCS does, unlike Python's exact integers). Tested
  in the module and from another project with its own struct (the generic
  crosses modules, as `json2.encode` does; no compiler trouble).
- V bug: `keys()` on the smart-cast map branch of a recursive sum type gives
  the wrong type (`regressions/smartcast_map_keys.vv`); worked around by
  collecting keys with `for k, _ in v`.
- Seven mutations (byte order for keys, the decimal and the 21-digit cutoffs,
  hmac unkeyed, control characters unescaped, no length check, a bad key
  replaced by a random one) each fail the tests.

### P5. Exporters

- **P5.1** The stdout exporter, one JSON line per span; a pretty option. (The
  `SpanExporter` interface came with P2.6, in `sdk/trace`.)
  *Done* (`exporters/stdout/stdout.v`, tests). `stdout.Exporter.new(pretty:,
  resource:, writer:)`; default standard output. One JSON object per span, in
  harness-trace-lab's JSONL style and a fixed key order: `name`, `trace_id`,
  `span_id`, `parent_span_id` (roots have none), `trace_state` (if any),
  `kind`, `start_time`/`end_time` (RFC 3339, UTC, nanoseconds), `duration_ms`
  (3 decimals), `status` (`code`, `description` if any), `attributes` (an
  object), `events`, `links`, `scope` (`name`, `version` if any), the dropped
  counts when not 0, and `resource` with `resource: true` (off by default: it
  repeats on every line). `pretty: true` indents the same object by two spaces.
  Built as a small ordered tree (`Node`), so both modes share one writer.
  NaN and infinities are strings (JSON has neither); control characters are
  `\u00xx`; text that isn't UTF-8 has its high bytes as `\u00xx`, so every line
  stays valid JSON (tests decode each). Writes under a lock, all bytes or an
  error; after `shutdown`, exports fail. Tested with exact lines from the SDK
  (sequential ids, fixed times); four mutations fail them.
- **P5.2** OTLP JSON encoding: `resourceSpans` → `scopeSpans` → `spans`, ids as
  hex, times as strings of unix nanoseconds, `intValue` as a string, attributes as
  `{key, value: {stringValue | ...}}`, events, links, status, kind as its number.
  Tests against golden JSON from the OTLP spec's examples.
  *Done* (`exporters/otlphttp/encode.v`, tests, `testdata/`; the ordered JSON
  writer moved from `stdout` to `exporters/internal/jsonw`, kept out of the API
  docs by `.vdocignore`). `encode_traces(spans, pretty) string`: an
  `ExportTraceServiceRequest` grouped by resource, then scope, in first-seen
  order; `schemaUrl` at both levels. Ids lowercase hex; times and `intValue` as
  strings; `kind` as OTLP's number (internal 1 … consumer 5, mapped, since
  otel's enum starts at 0); status `{message, code}` with otel's numbers; a
  NaN `doubleValue` as `"NaN"`; arrays as `{"arrayValue":{"values":[…]}}`;
  defaults (empty, zero, unset status) left out. `flags` on spans and links is
  the trace flags plus `0x100` (remote known) and `0x200` (remote), as Go does.
  - `testdata/otlp_example_trace.json` is the OTLP repository's
    `examples/trace.json`; the encoder reproduces every field of it (hex
    compared without case: the example is upper case, we write lower, both
    valid). `testdata/traces_golden.json` covers every value type, events,
    links, dropped counts, statuses and grouping; reviewed field by field
    against the spec; regenerate with `UPDATE_GOLDEN=1`.
  - Four mutations (kind from 0, `intValue` as a number, no remote bits, scope
    grouping ignored) fail the tests.
- **P5.3** OTLP/HTTP client: endpoint and header env vars, `/v1/traces` path rules
  (the generic endpoint gets the path added, the traces one doesn't), timeout,
  one retry on 429/502/503/504 honoring `Retry-After`.
  *Done* (`exporters/otlphttp/otlphttp.v`, `otlphttp_test.v`).
  `otlphttp.Exporter.new(endpoint:, headers:, timeout:) !` implements
  `trace.SpanExporter`: one POST of `encode_traces` per batch,
  `Content-Type: application/json`, `User-Agent: OTel-OTLP-Exporter-V/<version>`.
  - URL: code's `endpoint` (the full traces URL), else
    `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` as is, else
    `OTEL_EXPORTER_OTLP_ENDPOINT` + `v1/traces` after its own path, else
    `http://localhost:4318/v1/traces`. Headers: the general variable, then the
    traces one key by key, then code's; `k=v` with percent-decoded values.
    Timeout: code, else the traces then general variable (ms), else 10 s.
  - Section 1's rule: a malformed endpoint (no http/https scheme or host) is an
    error; a bad header entry, timeout, or a protocol other than `http/json` is
    a warning and the default. Warnings name an entry, never its value (a
    header may be an API key).
  - Retry: 2xx is success; 429/502/503/504 get one more try after
    `Retry-After` (seconds or an HTTP date) or 1 s, unless that passes the
    timeout; any other status, a second failure, or a network error fails the
    export with the status and up to 200 characters of the body. `net.http`'s
    own socket retries are off (`max_retries: 1`, which is one attempt; 0 was
    none at all, found in P5.6).
  - The HTTP call is a private `Transport`; tests script a fake and record
    waits, so none sleeps. P5.6 tests the real one against a local server.
  - Compiling `net.http` (TLS, HTTP/2) takes about 20 s per test file with
    `-nocache`; the price of the cache workaround (P2.4).
  - Four mutations (retry on any 4xx/5xx, `Retry-After` ignored, the trailing
    slash rule, code headers dropped) fail the tests.
  - Not done: gzip (`OTEL_EXPORTER_OTLP_COMPRESSION`), TLS client options, and
    reading a 2xx `partial_success` body; later if asked.
- **P5.4** Batch processor, part 1: the channel, the queue limit and drop counter
  (readable as `dropped()`), the worker thread exporting by size.
  *Done* (`sdk/trace/batch_processor.v`, `batch_processor_test.v`; in
  `sdk/trace` beside the simple processor, as in Go).
  `BatchSpanProcessor.new(exporter, max_queue_size: 2048, max_export_batch_size:
  512, on_error:)`. `on_end` puts a sampled span on a buffered channel with
  `try_push`: never waits; a full queue drops and counts (`dropped() u64`). One
  worker thread fills a batch and exports it at the batch size; export errors
  go to `on_error` (stderr by default). `shutdown` (once): closes the queue,
  the worker exports what is left, waits for it, then the exporter's
  `shutdown`; later spans are ignored, not counted. A batch size above the
  queue size is cut to it. `force_flush` returns at once until P5.5.
  - Tests: batches of 3,3 then 1 at shutdown in order; unsampled skipped; a
    held exporter with a queue of 4 drops exactly 5 of 9 without waiting; late
    spans ignored; errors to `on_error`; 8 threads × 500 spans through a
    provider all exported in batches of 100 or fewer. 20 runs (10 under
    `-prod`) without a failure.
  - Three mutations (a blocking push, no drain at shutdown, batches one too
    big) fail the tests. Two first hung the test rather than failing it; the
    test now waits with `select` timeouts and ends spans from its own thread,
    so a hang becomes a failure in seconds, not a 20-minute CI timeout.
- **P5.5** Batch processor, part 2: export by time, `force_flush`, `shutdown`
  with a timeout; env vars `OTEL_BSP_*`.
  *Done* (`sdk/trace/batch_processor.v` reworked, tests added).
  - The worker waits in one `select` on the span queue, a control channel and
    the schedule delay. A full batch goes out at once; otherwise what it holds
    goes out when `schedule_delay` (5 s) passes. The queue is no longer
    closed: `force_flush` and `shutdown` send a request with a reply channel,
    the worker drains the queue (`try_pop`) in full batches and the rest,
    answers, and on `stop` ends. Spans ended after shutdown are ignored.
  - `force_flush` and `shutdown` wait at most `export_timeout` (30 s), for
    sending the request as well as for the answer, then fail with "took longer
    than …; queued spans may be lost"; `shutdown` still shuts the exporter
    down. The bound on the send was a bug found here: a timed-out flush left
    its request in the one-slot channel, and a later `shutdown` blocked on it
    forever. The test now runs both on a thread of their own with `select`
    timeouts, so such a hang fails in seconds.
  - Options are `?` (code, then `OTEL_BSP_SCHEDULE_DELAY`,
    `OTEL_BSP_EXPORT_TIMEOUT` (ms), `OTEL_BSP_MAX_QUEUE_SIZE`,
    `OTEL_BSP_MAX_EXPORT_BATCH_SIZE`, then defaults); a value that isn't a
    whole number above 0 is a warning and the default; a batch above the
    queue is cut to it, with a warning. `config()` returns what is used.
  - Tests: a part-full batch out after the delay; flush exporting what is
    queued and the processor running on; flush and shutdown giving up behind a
    stuck export; the provider's flush; the settings and their warnings. 20
    runs and 10 under `-prod` clean. Six mutations (unbounded request send,
    timer not exporting, flush not draining, `0` accepted, and P5.4's) fail.
- **P5.6** Fake collector tests: a `net.http` server in the test that records
  bodies; batching by size and time, drop on a full queue, retry on 503, flush on
  shutdown.
  *Done* (`exporters/otlphttp/collector_test.v`). A `net.http.Server` on a
  free port (`127.0.0.1:0`) answers from a script (503 with `Retry-After: 0`,
  400 with a body, else 200), can hold a request until released, and records
  method, path, headers and body. The SDK, a batch processor, this exporter
  and `net.http` run as an app would: full batches then the rest at shutdown
  (`[a b] [c d] [e]`), headers (`application/json`, the API key, the user
  agent); a part batch after the delay; a 503 retried once with the same body
  and the spans arriving once; a 400 reported to `on_error` with its body and
  not retried; a held collector costing two spans of five, none waiting; a
  collector that is gone reported. 15 runs clean; dropping the retry fails it.
  - **Bug found in P5.3:** `max_retries: 0` in `http.fetch` meant no attempt
    at all ("exhausted retries"): net.http counts attempts, not retries. Now
    1. P5.3's fake transport couldn't see it; this test did on its first run.
- **P5.7** By hand: the OpenTelemetry Collector in Docker with the `debug`
  exporter, and Jaeger all-in-one. Record the commands in the README.
  *Done* (2026-10-14; README section "Seeing spans in a collector and
  Jaeger"). Collector `otel/opentelemetry-collector-contrib:0.120.0` (OTLP/HTTP
  on 4318, `debug` exporter, forwarding OTLP/gRPC to Jaeger) and
  `jaegertracing/jaeger:2.4.0` on a `otel-dev` Docker network. A scratch
  program sent a three-level trace (remote parent from a `traceparent`, every
  attribute type, an event, `record_error`, an error status, a plain ref)
  through the batch processor and `otlphttp`. The collector's debug output
  showed every field as sent (ids, parents, kinds, types, the resource's
  `telemetry.sdk.*`, `exception.type` without a message); Jaeger's API
  returned the trace under `otel-v-smoke` with the parent chain intact and
  durations nested (3,828 > 3,801 > 3,389 µs). The README's config is inline,
  so it needs no file from the repository; P6.2 puts the same in a
  `docker-compose.yml`.

### P6. Examples and docs

All in vgraph's shape (section 1): examples with their own `v.mod`, README and
`main_test.v`; every code block in the docs from `docs/snippets`.

- **P6.1** `examples/http_service`: a `veb` or `net.http` app that extracts
  `traceparent`, starts a server span, a child span, and exports to a collector;
  `main_test.v` runs it against the in-memory exporter.
- **P6.2** `examples/http_service`, part 2: a `docker-compose.yml` with the
  Collector and Jaeger, and the README's steps to see the waterfall.
- **P6.3** `examples/refs`: hashing a payload, then finding it again with the key.
- **P6.4** `docs/README.md` index and `docs/getting-started.md` (install, a
  provider, a span, export), its code in `docs/snippets`.
- **P6.5** `docs/configuration.md` (the environment variables, samplers,
  propagators) and `docs/refs.md` (modes, length, keys, canonical JSON, what a
  ref does and doesn't protect).
- **P6.6** `docs/instrumenting-a-library.md`: taking a provider (Q2), spans from
  the context, written for vgraph's work from section 3.
- **P6.7** README: what's there and what isn't (traces only, JSON only), status
  with the V commit, a quick start from the snippets, links to the guides.

*P6 done* (2026-10-14, the seven blocks in one run at the user's request).
- P6.1 `examples/http_service` on `net.http.Server` (not veb: the tracing is the
  point). `app.v`: per request, the caller's trace through a `GetterCarrier`
  over `req.header.get_custom`, a server span `GET /hello` (or `GET unknown`)
  with `http.request.method`, `url.path`, `http.route`,
  `http.response.status_code`, a child span `greet`, and an `X-Trace-Id`
  response header. `main.v`: `otlphttp` + batch processor from the environment,
  `PORT`, and ctrl-c shutting the provider down so queued spans go out.
  `main_test.v` over HTTP on a free port with an in-memory exporter: a
  continued trace, a new one, a 404, an unsampled caller followed. HTTP names
  added to `semconv`.
- P6.2 `docker-compose.yml` and `collector.yaml` (the P5.7 stack). Run for real:
  `GET /hello` under the caller's span in Jaeger, `greet` its child, two traces
  under `http_service`, both sent by the ctrl-c shutdown. (A first run went
  wrong because a broad `pkill -f` stopped the containers too: signal by PID.)
- P6.3 `examples/refs`: `record` (four tool calls of a billing agent, each span
  with `tool.args_ref`, written by the stdout exporter to `traces.jsonl`) and
  `find '<json>'` (the ref again, the spans with it). Tests: Alice's calls
  found in any key order, no email, account or subject in the file, another key
  finds nothing. Run by hand with an `openssl` key, and without one (each run
  its own key, nothing found, as the README explains). `traces.jsonl` ignored.
- P6.4 `docs/README.md` (index), `docs/getting-started.md` (install, provider,
  spans, propagation, shutdown, seeing them). `docs_test.v` has its
  `assert checked > 0` back; a hand-made drift fails it with the line and fix.
- P6.5 `docs/configuration.md` (every variable, by area, with defaults; which
  bad values warn and which are errors) and `docs/refs.md` (modes, keys,
  length, JCS, `from_struct`, the Python vectors, what a ref doesn't protect).
- P6.6 `docs/instrumenting-a-library.md`: a provider option defaulting to
  `noop_tracer_provider()` (an interface default in `@[params]` works), the
  caller's context, explicit times and their resolution, what a span carries,
  testing with the in-memory exporter.
- P6.7 README: what it is, status, a quick start (a snippet whose test sends it
  to a local server standing in for a collector), what it does and doesn't, docs
  and examples, the collector commands, contributing in vgraph's shape.
- Snippets (`docs/snippets`): `tracing.v`, `configured.v`, `refs.v`,
  `library.v`, `quickstart.v`, each run by a test. Every ```v block in the
  README and guides comes from them (no `v ignore` loophole).

### P7. Release v0.1.0

- **P7.1** Benchmarks: no-op span start and end, sampled span to an in-memory
  exporter; numbers in the README.
- **P7.2** Last pass: `v vet` clean, every `pub` documented, examples run,
  version `0.1.0`. This file is deleted.

## 5. Later releases (cut into blocks when each starts)

**v0.2.0 metrics.** API: `MeterProvider`, `Meter`, sync instruments (counter,
up-down counter, histogram, gauge) and async ones (observable counter, up-down
counter, gauge with callbacks). SDK: aggregation (sum, last value, explicit-bucket
histogram), cumulative and delta temporality, a periodic reader, views (rename,
drop attributes, change buckets), cardinality limits. OTLP JSON for `/v1/metrics`,
stdout. Exemplars after.

**v0.3.0 logs and events.** The Logs bridge API (`LoggerProvider`, `Logger`,
`emit`), log records tied to the active span, the batch log processor, OTLP
`/v1/logs`; the Events API on top. A bridge from V's `log` module.

**Stretch.**
- An experimental agent harness in V, using spans, refs and a payload channel;
  decide from it whether GenAI semantic conventions (`gen_ai.*`) belong here as
  `five07.otel.semconv.genai` or stay with integrators.
- OTLP over gRPC (needs a hand-written protobuf encoder; `net.http` has an
  HTTP/2 client), and OTLP/HTTP with protobuf.
- Resource detectors (host, process, container), a Prometheus exporter, more
  propagators if asked.

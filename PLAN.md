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
  block, run `v fmt -w`, `v vet` and `v test` on what it touched, report, and stop.
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
  the statement did);
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
- **P2.2** `Resource` in `sdk.resource`: attributes, merge,
  `telemetry.sdk.name/language/version`, `service.name` from `OTEL_SERVICE_NAME`,
  `OTEL_RESOURCE_ATTRIBUTES` parsing; tests.
- **P2.3** `RecordingSpan`: holds name, kind, context, parent, times (unix ns),
  attributes, events, links, status; setters guarded by a mutex and ignored after
  `end()`; attribute and event limits (128 each, as the spec defaults) with
  dropped counts.
- **P2.4** `TracerProvider` and `Tracer`: `start` picks the parent from the context
  (or a new root), asks the sampler, makes a recording or a non-recording span;
  instrumentation scope (name, version) on each span.
- **P2.5** Samplers (Q7): AlwaysOn, AlwaysOff, TraceIdRatioBased, ParentBased;
  env vars; tests with the decisions carried to children.
- **P2.6** `SpanProcessor` interface (`on_start`, `on_end`, `force_flush`,
  `shutdown`), `SimpleSpanProcessor`, an in-memory exporter for tests;
  `provider.shutdown()` and `force_flush()` reach every processor.
- **P2.7** `record_error` (Q8), `add_event`, links; tests of parenting across three
  levels, status rules (ok can't go back to unset or error), end times.

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

### P5. Exporters

- **P5.1** `SpanExporter` interface (`export([]ReadOnlySpan) !`, `shutdown`); the
  stdout exporter, one JSON line per span; a pretty option.
- **P5.2** OTLP JSON encoding: `resourceSpans` → `scopeSpans` → `spans`, ids as
  hex, times as strings of unix nanoseconds, `intValue` as a string, attributes as
  `{key, value: {stringValue | ...}}`, events, links, status, kind as its number.
  Tests against golden JSON from the OTLP spec's examples.
- **P5.3** OTLP/HTTP client: endpoint and header env vars, `/v1/traces` path rules
  (the generic endpoint gets the path added, the traces one doesn't), timeout,
  one retry on 429/502/503/504 honoring `Retry-After`.
- **P5.4** Batch processor, part 1: the channel, the queue limit and drop counter
  (readable as `dropped()`), the worker thread exporting by size.
- **P5.5** Batch processor, part 2: export by time, `force_flush`, `shutdown`
  with a timeout; env vars `OTEL_BSP_*`.
- **P5.6** Fake collector tests: a `net.http` server in the test that records
  bodies; batching by size and time, drop on a full queue, retry on 503, flush on
  shutdown.
- **P5.7** By hand: the OpenTelemetry Collector in Docker with the `debug`
  exporter, and Jaeger all-in-one. Record the commands in the README.

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

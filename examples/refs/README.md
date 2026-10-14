# refs

Naming the payloads of an agent's tool calls in its spans without putting them
there, then finding the spans for a payload you know.

An agent's tool arguments often hold personal data: an email, an account
number. Its spans need to say which calls used which data, so an engineer can
follow a customer's request through the traces, but the data must not reach
the telemetry backend. A keyed ref does both: `tool.args_ref` is
`hmac:` and 32 hex characters of HMAC-SHA256 over the arguments' canonical JSON.
Without the key, it says nothing about the arguments, even ones easy to guess;
with the key, you can make the ref of `{"email": "alice@example.com"}` again and
search for it.

Built and tested with V master, like otel (see the root README). It imports otel
as `five07.otel`, so run `v run ../setup.vsh` once per checkout first.

## Running

```sh
export OTEL_REF_KEY=$(openssl rand -hex 32)       # keep it as you would a password
v -nocache run . record                            # the agent's run, into traces.jsonl
v -nocache run . find '{"email": "alice@example.com"}'
v -nocache run . find '{"to": "alice@example.com", "subject": "Invoice 42"}'
```

`record` writes one span per tool call to `traces.jsonl`, as the stdout exporter
writes them: the tool's name and `tool.args_ref`, and no argument. `find` makes
the ref of the JSON you give it and lists the spans with that ref:

```
lookup_customer in trace 7f8e6d7d081ab95d83a69b947e544a61, span df551c236befbc42
```

Key order and spacing don't matter: refs are made from canonical JSON (RFC 8785),
so `{"subject": …, "to": …}` finds the call made with `{"to": …, "subject": …}`.

Without `OTEL_REF_KEY`, each run makes up its own key and says so, and `find`
matches nothing `record` wrote: refs only join under the same key.

```sh
v -nocache test .                                  # the tests: finding, privacy, keys
```

`-nocache`: V master's default `v run` build can miscompile calls between
modules (see `regressions/run_cross_module_interface`).

## Layout

```
main.v       the command line: record, find
refs.v       the agent's calls, recording their spans, finding a payload's spans
main_test.v  finds Alice's calls, checks no payload reaches the file, and that
             another key finds nothing
```

See [refs](../../docs/refs.md) for the modes, lengths, keys, and what a ref does
and doesn't protect.

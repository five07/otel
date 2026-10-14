<!-- Thanks! Pull requests go to `develop`; `main` gets releases. -->

## What and why

<!-- What it changes, and the issue it fixes, if any: "Fixes #123". -->

## Checklist

- [ ] Tests: new behaviour has a test, and `v test .` passes (after
      `v run examples/setup.vsh` once per checkout); for a change to what is
      exported, the OTLP JSON tests pass against their golden files.
- [ ] Telemetry: nothing reaches a span, event or attribute that the caller
      didn't put there (no error messages, payloads or values by default).
- [ ] Docs: the guides and README say what changed; their code is in
      `docs/snippets` (`UPDATE_SNIPPETS=1 v test docs/snippets/docs_test.v`).
- [ ] `v fmt -verify .` and `v vet -W` pass, and every new `pub` item has a doc
      comment.
- [ ] A workaround for a V bug has a program in `regressions/`.

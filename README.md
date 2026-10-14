# otel

[OpenTelemetry](https://opentelemetry.io) for [V](https://vlang.io), on the
standard library alone. Libraries record spans through a small API that costs
nothing until an app turns it on; the app sends them to any collector over
OTLP/HTTP. Hashed refs name sensitive values in telemetry without revealing them.

**Status:** not usable yet; work toward v0.1.0 (traces) has started. Built
against V master at `04cb7fa` (2026-10-14), a daily build that still reports
`V 0.5.2`.

## License

MIT, see [LICENSE](LICENSE).

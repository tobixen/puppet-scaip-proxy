# Changelog

## [Unreleased]

### Fixed

- Use `xhttp_prom.so` (base `kamailio` package) instead of `prometheus.so`
  (absent from Kamailio 6.0 packages on Ubuntu 24.04), fixing startup failure
  when `metrics_enabled` is `true`.
- Remove erroneous `kamailio-extra-modules` dependency for metrics; the
  `xhttp_prom` module ships in the base package.

Initial implementation of the tobixen-scaip_proxy Puppet module.

Written from scratch as a purpose-built SCAIP SIP proxy module.
See docs/DECISIONS.md for rationale.

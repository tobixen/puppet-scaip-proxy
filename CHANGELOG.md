# Changelog

## [Unreleased]

### Fixed

- Rewrite Request-URI domain (`$rd`) and To header to the upstream host
  before forwarding. Previously the proxy hostname leaked into both fields,
  causing the upstream to reject the request with `408 Request Timeout`.
- Route requests from the upstream (R-URI ≠ myself) directly to the alarm
  device instead of looping them back to the upstream.
- Add `sip_domain` parameter (defaults to node FQDN) and emit it as a
  Kamailio `alias` so that `uri==myself` correctly recognises requests
  addressed to the proxy by its DNS hostname. Without this alias, all
  device requests fell through to `route(RELAY)`, Kamailio detected a
  forwarding loop to its own IP, and returned `483 Too Many Hops`
  without logging anything.

## [v0.2.0] - 2026-03-17

v0.2.0 is the first version that actually works.  I do not deem it important to list up all the changes since the repository was empty - refer to the README to see what the project is supposed to do.

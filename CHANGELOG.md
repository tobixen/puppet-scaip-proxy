# Changelog

## [Unreleased]

* New parameter `upstream_addresses`: requests from the upstream addressed to
  the proxy itself are answered and logged instead of being relayed back to it
* New parameter `http_listen_address` for the `/health`, `/ready` and
  `/metrics` endpoints
* TCP keepalive timers on SIP connections: first probe after 60 s idle instead
  of the kernel's 7200 s (`tcp_keepidle`, `tcp_keepintvl`, `tcp_keepcnt`;
  `tcp_keepalive: false` turns keepalive off)

## [v0.2.0] - 2026-03-23

v0.2.0 is the first version that actually works.  I do not deem it important to list up all the changes since the repository was empty - refer to the README to see what the project is supposed to do.

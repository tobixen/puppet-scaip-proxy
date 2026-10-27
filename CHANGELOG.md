# Changelog

## [Unreleased]

This is the first version that actually works.  I do not deem it important to list up all the changes since the repository was empty - refer to the README to see what the project is supposed to do.

* The `/health`, `/ready` and `/metrics` endpoints now answer ordinary HTTP
  clients; they used to return an empty reply
* New parameter `upstream_addresses`: requests from the upstream addressed to
  the proxy itself are answered and logged instead of being relayed back to it
* New parameter `additional_aliases`: more DNS names the proxy answers to, next
  to `sip_domain`
* The log line of each message routed upstream, and of each status from the
  upstream, carries the SCAIP message type, status code and reference
  (`log_alarm_fields`, default on; the caller id is never logged)
* New parameter `http_listen_address` for the `/health`, `/ready` and
  `/metrics` endpoints
* TCP keepalive timers on SIP connections: first probe after 60 s idle instead
  of the kernel's 7200 s (`tcp_keepidle`, `tcp_keepintvl`, `tcp_keepcnt`;
  `tcp_keepalive: false` turns keepalive off)
* `/metrics` exports kamailio's internal statistics (new parameter
  `metrics_stats`, default `all`)
* New parameter `ctl_enabled` (default on): `kamcmd` works, and a TLS
  configuration change is reloaded without restarting kamailio and dropping
  the device connections; a renewed certificate can be reloaded the same way
  (see the README)

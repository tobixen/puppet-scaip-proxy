# tobixen-scaip_proxy

Puppet module that installs and configures [Kamailio](https://www.kamailio.org/) as a
transparent SIP proxy for [SCAIP](https://www.scaip.org/) alarm devices on isolated RFC1918
networks. The proxy forwards alarm traffic to an upstream SCAIP server over TLS, handles
NAT traversal, and exposes health, readiness, and Prometheus metrics endpoints.

See [`docs/DECISIONS.md`](docs/DECISIONS.md) for the rationale behind the software choices.

Perhaps this module can be renamed and fixed into a general module for setting
up kamailio, but as I only need kamailio for this single purpose,
that's all the module can do as for now.

## Requirements

- **Puppet** 7.x or 8.x
- **OS**: Debian or Ubuntu (apt-based)
- **Puppet modules**: `puppetlabs/stdlib` (>= 8.0), `puppetlabs/apt` (>= 9.0)

## Usage

### Minimal

```puppet
class { 'scaip_proxy':
  upstream_host => 'sip.example.com',
}
```

This installs Kamailio 6.0.x from the official apt repository, configures it to forward
SCAIP traffic to the given upstream host on port 5061 over SIPS/TLS, and starts the service.

> **Important:** The `public_ip` parameter defaults to the node's primary NIC IP, which is
> almost certainly wrong for a dual-homed proxy. Always set it explicitly via Hiera.

### Recommended: set per-node values in Hiera

```yaml
# hiera data for the proxy node
scaip_proxy::upstream_host: 'sip.example.com'
scaip_proxy::public_ip: '203.0.113.10'
scaip_proxy::listen_address: '10.0.1.1'   # internal interface only
```

### Custom upstream

```puppet
class { 'scaip_proxy':
  public_ip        => '203.0.113.10',
  upstream_host    => 'sip.example.com',
  upstream_port    => 5061,
  upstream_scheme  => 'sips',
}
```

### Disable TLS (plain SIP upstream)

```puppet
class { 'scaip_proxy':
  tls_enabled     => false,
  upstream_scheme => 'sip',
  upstream_port   => 5060,
}
```

### Skip the apt repository (package already available)

```puppet
class { 'scaip_proxy':
  manage_repo => false,
}
```

### Install additional Kamailio modules

```puppet
class { 'scaip_proxy':
  extra_packages => ['kamailio-utils-modules', 'kamailio-presence-modules'],
}
```

## TLS certificates

TLS is enabled by default. The module manages the `/etc/kamailio/tls/` directory but does
**not** provision certificate files — bring your own via certbot/ACME, an internal PKI, or
another Puppet module:

| Parameter      | Default                                     |
|----------------|---------------------------------------------|
| `tls_cert_file`| `/etc/kamailio/tls/cert.pem`               |
| `tls_key_file` | `/etc/kamailio/tls/key.pem`                |
| `tls_ca_file`  | system CA bundle (`ca-certificates.crt`)   |

kamailio reads the certificate at startup.  With `ctl_enabled` (the default)
a change to `tls.cfg` runs `kamcmd tls.reload` instead of restarting
kamailio: new connections get the new configuration and certificate, and
established ones are left alone.  To pick up a renewed certificate the same
way, notify the refresh-only `Exec['scaip_proxy tls.reload']` from the
Puppet resource that renews it:

```puppet
File['/etc/ssl/private/sip.example.com.pem'] ~> Exec['scaip_proxy tls.reload']
```

The exec exists only when `manage_service`, `tls_enabled` and `ctl_enabled`
are all true, and it is skipped when kamailio does not answer `kamcmd`.  A
certificate renewed outside Puppet (certbot, say) needs its own deploy hook
running `kamcmd tls.reload`.

## Health and metrics endpoints

Kamailio exposes an HTTP server on port 8080 (configurable via `http_port`),
on `listen_address` unless `http_listen_address` says otherwise.  The
endpoints are plain http and unauthenticated:

| Path       | Description                                  |
|------------|----------------------------------------------|
| `/health`  | Returns `200 OK` — suitable for load balancers |
| `/ready`   | Returns `200 OK` — readiness probe            |
| `/metrics` | Prometheus metrics (requires `metrics_enabled => true`) |

The `/metrics` endpoint uses the `xhttp_prom` module, which is part of the base
`kamailio` package — no additional packages are required.  By default
(`metrics_stats => 'all'`) it exports every internal statistic, memory and
connection counts included, to anyone who reaches the port: bind it to
`127.0.0.1` with `http_listen_address`, or firewall it.

Serving these requires the core parameter `tcp_accept_no_cl=yes`, which the
generated config sets.  Without it, kamailio discards any TCP message that has
no `Content-Length` header — which is every ordinary HTTP `GET` — and closes
the connection, so all three paths answer an empty reply.  It can in principle
be changed at runtime (`kamcmd cfg.set_now_int tcp accept_no_cl 1`, with
`ctl_enabled`), but the module does not do that: changing it rewrites
`kamailio.cfg`, which means a kamailio restart.

`http_reply_parse=yes`, often suggested alongside it, is not set: the three
endpoints answer without it and nothing is logged, and it would make the core
parser accept an HTTP status line in any message, on the SIP listeners too.
Revisit this if a module that parses outgoing messages (`siptrace`, `topoh`)
or an `onsend_route` is added: those are what log an error on each
xhttp reply.

`tcp_accept_no_cl` is not limited to the HTTP port: it relaxes the
`Content-Length` requirement on every TCP and TLS listener, SIP included.  A
SIP message without `Content-Length` is accepted as bodiless instead of the
connection being closed - harmless when it has no body.  When it does have
one, the body is read as the next message on that connection and routed as a
SIP message of its own.  That can only confuse the traffic on the offending
peer's connection - which for a device is its own single transaction, but
for an upstream that multiplexes many devices' traffic on one connection is
everything behind it.  The module accepts that.

## Parameters

| Parameter         | Default                          | Description |
|-------------------|----------------------------------|-------------|
| `package_ensure`  | `installed`                      | Package ensure value (`installed`, `latest`, a version string, or `absent`) |
| `manage_repo`     | `true`                           | Add the official Kamailio apt repository |
| `kamailio_version`| `60`                             | Version string appended to the repo URL (`60` → kamailio60, i.e. 6.0.x) |
| `manage_config`   | `true`                           | Manage `/etc/kamailio/` config files |
| `manage_service`  | `true`                           | Manage the `kamailio` systemd service |
| `service_enable`  | `true`                           | Enable the service at boot |
| `service_ensure`  | `running`                        | Desired service state |
| `listen_address`  | `0.0.0.0`                        | IP address to listen on (restrict to internal interface in production) |
| `listen_port`     | `5060`                           | SIP UDP/TCP port |
| `listen_tls_port` | `5061`                           | SIPS TLS port |
| `public_ip`       | primary NIC IP                   | Public IP for Contact/Via NAT rewriting — **set this explicitly** |
| `sip_domain`      | node FQDN                        | DNS hostname of this proxy, added as a Kamailio alias so requests addressed by hostname are recognised as local |
| `additional_aliases` | `[]` | Further DNS names the proxy answers to, each a Kamailio alias; a name that is not an alias gets `404 Device Not Reachable` |
| `log_alarm_fields` | `true` | Add `mty` (message type), `stc` (status code) and `ref` from the SCAIP body to the log line of each message routed upstream, and of each status from the upstream; never the caller id (`cid`) |
| `upstream_host`   | **required**                     | Upstream SCAIP server hostname |
| `upstream_port`   | `5061`                           | Upstream SCAIP server port |
| `upstream_scheme` | `sips`                           | URI scheme for upstream (`sips` or `sip`) |
| `upstream_addresses` | `[]`                          | IPv4 source addresses of the upstream's own requests; those addressed to the proxy are answered and logged, never relayed (see below) |
| `tls_enabled`     | `true`                           | Enable TLS/SIPS support |
| `tls_cert_file`   | `/etc/kamailio/tls/cert.pem`     | TLS certificate PEM path |
| `tls_key_file`    | `/etc/kamailio/tls/key.pem`      | TLS private key PEM path |
| `tls_ca_file`     | `undef` (system bundle)          | CA bundle for verifying the upstream certificate |
| `debug_level`     | `2`                              | Kamailio verbosity (0=emergency … 9=debug; 5+ for troubleshooting) |
| `log_facility`    | `LOG_LOCAL0`                     | Syslog facility |
| `http_port`       | `8080`                           | Port for `/health`, `/ready`, `/metrics` |
| `http_listen_address` | `listen_address`             | IPv4 address for `/health`, `/ready`, `/metrics`; `127.0.0.1` keeps them off a routed address |
| `tcp_keepalive`   | `true`                           | Set the keepalive timers below on SIP connections; `false` turns kamailio's default keepalive off |
| `tcp_keepidle` / `tcp_keepintvl` / `tcp_keepcnt` | `60` / `10` / `3` | Idle seconds before the first probe, seconds between probes, probes before giving up |
| `metrics_enabled` | `true`                           | Enable Prometheus `/metrics` endpoint |
| `metrics_stats`   | `all`                            | kamailio internal statistics exported on `/metrics` (`all`, a group such as `tm:`, or one statistic; empty for none) |
| `ctl_enabled`     | `true`                           | Load `ctl.so` for `kamcmd`; a `tls.cfg` change becomes a `tls.reload` instead of a restart (see TLS certificates) |
| `extra_packages`  | `[]`                             | Additional `kamailio-*` packages to install |

## Limitations and known caveats

### NAT keepalives not implemented

The module does **not** send active OPTIONS keepalives to natted clients.
Kamailio's `nathelper` module can do this via `natping_interval`, but that
feature requires the `usrloc` (location database) module, which is not loaded
here because this is a pure forwarding proxy with no registrar.

If alarm devices lose their NAT mapping while idle (no in-progress call), new
inbound traffic from the upstream toward the device will fail until the device
re-establishes the connection. Mitigations:

- Configure the alarm devices to send their own SIP keepalives (OPTIONS or
  re-REGISTER) at an interval shorter than the NAT binding timeout.
- Use TLS, which typically uses TCP and therefore has persistent connections
  that survive as long as both ends keep the socket open (TCP keepalives or
  application-level pings from the device).
- If active pings from the proxy side are required, add `usrloc` and a
  REGISTER handler — but that turns this proxy into a registrar, which is
  a significant scope change.

### Requests from the upstream are not delivered to devices

Some upstreams send a request of their own after each alarm (a status
MESSAGE).  They send it over the connection the proxy opened to them,
addressed to the proxy's own socket rather than to the Contact alias the
proxy supplied, so it cannot be routed to a device - and with
`uri==myself` true for it, the default configuration relays it straight
back upstream.  Set `upstream_addresses` to the upstream's addresses to
answer such requests with `200 OK` and log them ("Status from ... not
relayed") instead.  Only requests addressed to the proxy itself are
absorbed; one the upstream addresses to a device alias still goes to the
device.  The proxy's own socket is the source of its connection to the
upstream, the node IP, so that is a Kamailio alias too when `public_ip`
differs from it; without `upstream_addresses` such a status is then
relayed back upstream rather than failing.  The addresses are the upstream's to change; keep the
list in step with its DNS.

### TCP keepalive

kamailio has TCP keepalive on by default, but with the kernel's timers: the
first probe after 7200 s idle.  Connections to the upstream are held open and
idle for minutes between alarms, and kamailio's `TCP_USER_TIMEOUT` only covers
data in flight, so a path that dies while idle (NAT or firewall state
expiring, an upstream restart) would only be found by the next alarm, which
then waits for the timeout.  The module therefore sets `tcp_keepidle`,
`tcp_keepintvl` and `tcp_keepcnt` (60/10/3 by default); keep `tcp_keepidle`
below the shortest idle timeout on the path.  The timers apply to every SIP
connection, device side included - harmless for devices that hang up after a
few seconds, but a device holding a connection open idle gets probed too.
`tcp_keepalive => false` turns keepalive off altogether.

### RTP media relay not included

This module only proxies **SIP signalling**. If a SCAIP call involves an RTP
media stream (e.g. two-way voice to an alarm operator) and either endpoint is
behind NAT, the media will not traverse the proxy — only the SIP headers are
rewritten.

To relay media you would need a media proxy such as
[rtpengine](https://github.com/sipwise/rtpengine) (Kamailio module:
`kamailio-rtpengine-modules`) integrated into the routing logic. Whether this
is required depends on the SCAIP profile in use and the network topology:

- If the upstream SCAIP server can reach the alarm device's private IP
  directly (e.g. via a routed VPN or the upstream does its own NAT traversal),
  no media relay is needed.
- If both the alarm device and the upstream server reach each other only via
  this proxy, a media relay is required for audio to work.

### SNI / multiple certificates not supported

The module configures a single TLS certificate for all incoming connections.
Kamailio's TLS module does support SNI (named `[server:hostname]` sections in
`tls.cfg`), but this module only exposes a single `tls_cert_file`/`tls_key_file`
pair.

This matters if you want to serve multiple brand hostnames from the same proxy
(e.g. `scaip-proxy.acme.com` and `scaip-proxy.emca.com`) each with their own
certificate. Workarounds:

- **SAN certificate**: order a single certificate with all hostnames as Subject
  Alternative Names. All brands share one cert; no module changes needed.
- **Extend the module**: add a `tls_domains` hash parameter and expand
  `tls.cfg.erb` to emit one `[server:hostname]` section per entry. The routing
  logic is unaffected — all brands forward to the same upstream regardless.

## Development

```bash
# Install dependencies
bundle install

# Run unit tests
bundle exec rake spec

# Lint
bundle exec rake lint

# Validate manifests and templates
bundle exec rake validate
```

CI runs on GitHub Actions against Puppet 7 and 8.

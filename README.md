# tobixen-scaip_proxy

Puppet module that installs and configures [Kamailio](https://www.kamailio.org/) as a
transparent SIP proxy for [SCAIP](https://www.scaip.org/) alarm devices on isolated RFC1918
networks. The proxy forwards alarm traffic to a Skyresponse SCAIP server over TLS, handles
NAT traversal, and exposes health, readiness, and Prometheus metrics endpoints.

See [`docs/DECISIONS.md`](docs/DECISIONS.md) for the rationale behind the software choices.

## Requirements

- **Puppet** 7.x or 8.x
- **OS**: Debian or Ubuntu (apt-based)
- **Puppet modules**: `puppetlabs/stdlib` (>= 8.0), `puppetlabs/apt` (>= 9.0)

## Usage

### Minimal (all defaults)

```puppet
include scaip_proxy
```

This installs Kamailio 6.0.x from the official apt repository, configures it to forward
SCAIP traffic to `prod2.voip.skyresponse.com:5061` over SIPS/TLS, and starts the service.

> **Important:** The `public_ip` parameter defaults to the node's primary NIC IP, which is
> almost certainly wrong for a dual-homed proxy. Always set it explicitly via Hiera.

### Recommended: set per-node values in Hiera

```yaml
# hiera data for the proxy node
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

## Health and metrics endpoints

Kamailio exposes an HTTP server on port 8080 (configurable via `http_port`):

| Path       | Description                                  |
|------------|----------------------------------------------|
| `/health`  | Returns `200 OK` — suitable for load balancers |
| `/ready`   | Returns `200 OK` — readiness probe            |
| `/metrics` | Prometheus metrics (requires `metrics_enabled => true`) |

The `/metrics` endpoint requires the `kamailio-extra-modules` package, installed
automatically when `metrics_enabled` is `true` (the default).

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
| `upstream_host`   | `prod2.voip.skyresponse.com`     | Skyresponse SCAIP server hostname |
| `upstream_port`   | `5061`                           | Skyresponse SCAIP server port |
| `upstream_scheme` | `sips`                           | URI scheme for upstream (`sips` or `sip`) |
| `tls_enabled`     | `true`                           | Enable TLS/SIPS support |
| `tls_cert_file`   | `/etc/kamailio/tls/cert.pem`     | TLS certificate PEM path |
| `tls_key_file`    | `/etc/kamailio/tls/key.pem`      | TLS private key PEM path |
| `tls_ca_file`     | `undef` (system bundle)          | CA bundle for verifying the upstream certificate |
| `debug_level`     | `2`                              | Kamailio verbosity (0=emergency … 9=debug; 5+ for troubleshooting) |
| `log_facility`    | `LOG_LOCAL0`                     | Syslog facility |
| `http_port`       | `8080`                           | Port for `/health`, `/ready`, `/metrics` |
| `metrics_enabled` | `true`                           | Enable Prometheus `/metrics` endpoint |
| `extra_packages`  | `[]`                             | Additional `kamailio-*` packages to install |

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

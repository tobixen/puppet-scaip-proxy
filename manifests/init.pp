# @summary Deploy Kamailio as a SCAIP SIP proxy for isolated RFC1918 networks
#
# Installs Kamailio and configures it as a transparent SIP proxy that forwards
# SCAIP alarm traffic from clients on an isolated network to a configured
# upstream SCAIP server over TLS.
#
# See docs/DECISIONS.md for rationale on software choices.
#
# @param package_ensure
#   Package ensure value (installed, latest, absent, or a version string).
#
# @param manage_repo
#   Whether to add the official Kamailio apt repository.
#
# @param kamailio_version
#   Version string used in the Kamailio repo URL (e.g. '60' for 6.0.x).
#
# @param manage_config
#   Whether to manage Kamailio configuration files under /etc/kamailio.
#
# @param manage_service
#   Whether to manage the kamailio systemd service.
#
# @param service_enable
#   Whether to enable kamailio at boot.
#
# @param service_ensure
#   Desired service state: 'running' or 'stopped'.
#
# @param listen_address
#   IP address Kamailio listens on. Use '0.0.0.0' for all interfaces, or
#   restrict to the internal interface IP for tighter security.
#
# @param listen_port
#   SIP UDP/TCP port (default 5060).
#
# @param listen_tls_port
#   SIPS TLS port (default 5061).
#
# @param public_ip
#   Public IP of this server, used to rewrite Contact/Via headers for NAT.
#   This MUST be set via Hiera per server — the default (primary NIC IP) is
#   almost certainly wrong for a dual-homed proxy.
#
# @param upstream_host
#   SCAIP server hostname. Mandatory — no default is provided.
#
# @param upstream_port
#   Upstream SCAIP server port.
#
# @param upstream_scheme
#   URI scheme for the upstream connection ('sips' or 'sip').
#
# @param tls_enabled
#   Enable TLS/SIPS support. Required for scaips:// upstream.
#
# @param tls_cert_file
#   Path to the TLS certificate PEM file. The certificate must be placed here
#   outside of Puppet (e.g. via certbot/ACME or an internal PKI).
#
# @param tls_key_file
#   Path to the TLS private key PEM file.
#
# @param tls_ca_file
#   Path to a CA bundle for verifying the upstream certificate.
#   Defaults to the system CA bundle (/etc/ssl/certs/ca-certificates.crt).
#
# @param debug_level
#   Kamailio debug verbosity (0=emergency .. 9=debug; 2 is suitable for
#   production, 5+ for troubleshooting).
#
# @param log_facility
#   Syslog facility for Kamailio log output.
#
# @param http_port
#   TCP port for the built-in HTTP server that serves /health, /ready, and
#   /metrics endpoints.
#
# @param metrics_enabled
#   Enable the Prometheus metrics endpoint at /metrics.
#   Uses xhttp_prom.so, which is included in the base kamailio package.
#
# @param extra_packages
#   Additional kamailio-* packages to install (e.g. ['kamailio-utils-modules']).
#
class scaip_proxy (
  $package_ensure   = $scaip_proxy::params::package_ensure,
  $manage_repo      = $scaip_proxy::params::manage_repo,
  $kamailio_version = $scaip_proxy::params::kamailio_version,
  $manage_config    = $scaip_proxy::params::manage_config,
  $manage_service   = $scaip_proxy::params::manage_service,
  $service_enable   = $scaip_proxy::params::service_enable,
  $service_ensure   = $scaip_proxy::params::service_ensure,
  $listen_address   = $scaip_proxy::params::listen_address,
  $listen_port      = $scaip_proxy::params::listen_port,
  $listen_tls_port  = $scaip_proxy::params::listen_tls_port,
  $public_ip        = $scaip_proxy::params::public_ip,
  $upstream_host    = $scaip_proxy::params::upstream_host,
  $upstream_port    = $scaip_proxy::params::upstream_port,
  $upstream_scheme  = $scaip_proxy::params::upstream_scheme,
  $tls_enabled      = $scaip_proxy::params::tls_enabled,
  $tls_cert_file    = $scaip_proxy::params::tls_cert_file,
  $tls_key_file     = $scaip_proxy::params::tls_key_file,
  $tls_ca_file      = $scaip_proxy::params::tls_ca_file,
  $debug_level      = $scaip_proxy::params::debug_level,
  $log_facility     = $scaip_proxy::params::log_facility,
  $http_port        = $scaip_proxy::params::http_port,
  $metrics_enabled  = $scaip_proxy::params::metrics_enabled,
  $extra_packages   = $scaip_proxy::params::extra_packages,
) inherits scaip_proxy::params {

  if $upstream_host == undef {
    fail('scaip_proxy: upstream_host is required — set it via Hiera or as a class parameter')
  }

  $base_packages = $tls_enabled ? {
    true    => ['kamailio', 'kamailio-tls-modules'],
    default => ['kamailio'],
  }

  $metrics_packages = []

  $all_packages = union($base_packages, $metrics_packages, $extra_packages)

  if $manage_repo {
    include apt

    # NOTE: verify the GPG key fingerprint against https://deb.kamailio.org/kamailiodebkey.gpg
    # before deploying to production:
    #   curl -s https://deb.kamailio.org/kamailiodebkey.gpg | gpg --show-keys
    apt::source { 'kamailio':
      location => "https://deb.kamailio.org/kamailio${kamailio_version}",
      release  => $facts['os']['distro']['codename'],
      repos    => 'main',
      key      => {
        'id'     => 'E79ACECB87D8DCD23A20AD2FFB40D3E6508EA4C8',
        'source' => 'https://deb.kamailio.org/kamailiodebkey.gpg',
      },
    }

    Apt::Source['kamailio'] -> Package[$all_packages]
  }

  package { $all_packages:
    ensure => $package_ensure,
  }

  if $manage_config {
    file { '/etc/kamailio/tls':
      ensure  => directory,
      owner   => 'root',
      group   => 'kamailio',
      mode    => '0750',
      require => Package[$all_packages],
    }

    file { '/etc/kamailio/kamailio.cfg':
      ensure  => file,
      owner   => 'root',
      group   => 'kamailio',
      mode    => '0640',
      content => template('scaip_proxy/kamailio.cfg.erb'),
      require => Package[$all_packages],
    }

    file { '/etc/kamailio/tls.cfg':
      ensure  => file,
      owner   => 'root',
      group   => 'kamailio',
      mode    => '0640',
      content => template('scaip_proxy/tls.cfg.erb'),
      require => Package[$all_packages],
    }

    file { '/etc/default/kamailio':
      ensure  => file,
      owner   => 'root',
      group   => 'root',
      mode    => '0644',
      content => template('scaip_proxy/kamailio_defaults.erb'),
      require => Package[$all_packages],
    }
  }

  if $manage_service {
    service { 'kamailio':
      ensure => $service_ensure,
      enable => $service_enable,
    }

    if $manage_config {
      File['/etc/kamailio/kamailio.cfg'] ~> Service['kamailio']
      File['/etc/kamailio/tls.cfg']      ~> Service['kamailio']
      File['/etc/default/kamailio']      ~> Service['kamailio']
    }

    Package[$all_packages] -> Service['kamailio']
  }
}

# vim: set et sw=2:

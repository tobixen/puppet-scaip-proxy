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
# @param sip_domain
#   SIP domain (DNS hostname) of this proxy.  Kamailio uses this as an alias
#   so that uri==myself correctly matches requests addressed to the proxy by
#   hostname (e.g. sip:alarm@skyresponse-proxy.example.com).  Defaults to the
#   node FQDN.  Set explicitly if the proxy DNS name differs from the FQDN.
#
# @param upstream_host
#   SCAIP server hostname. Mandatory — no default is provided.
#
# @param upstream_addresses
#   Source addresses the upstream sends its own requests from (the status
#   MESSAGE that follows each alarm).  Those arrive over our own upstream
#   connection addressed to our socket, so uri==myself is true for them;
#   without this list they are relayed straight back upstream.  With it,
#   those addressed to the proxy itself are answered with 200 and logged,
#   and relayed nowhere; one addressed to a device alias still goes to the
#   device.  Empty (the default) keeps the old behaviour.  IPv4 only.  The
#   set is the upstream's to change, so it has to be kept in step with its
#   DNS.
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
# @param children
#   Number of worker processes per UDP socket. Default 4 (2 per CPU core is
#   typical). Set to 1 to minimise process count and memory use for debugging.
#
# @param shm_mem_size
#   Shared memory pool size in MB. Default 64. Can be reduced to 8-16 on
#   memory-constrained nodes or for short debug sessions.
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
# @param http_listen_address
#   Address of that HTTP server.  Defaults to listen_address.  The endpoints
#   are plain http and unauthenticated, so set it to 127.0.0.1 if
#   listen_address is routed and nothing outside the node needs them.
#   IPv4 only.
#
# @param tcp_keepalive
#   TCP keepalive on SIP connections - all of them, device side included.
#   kamailio enables it by default, but with the kernel's timers (7200 s
#   idle before the first probe), which is useless for upstream connections
#   that sit idle for minutes: kamailio's TCP_USER_TIMEOUT only covers data
#   in flight, so a path that dies while idle is only found by the next
#   alarm.  With true the three timers below are set; false turns kamailio's
#   default keepalive off.
#
# @param tcp_keepidle
#   Seconds of idleness before the first probe.  Keep it below the shortest
#   NAT or firewall idle timeout on the path.
#
# @param tcp_keepintvl
#   Seconds between probes.
#
# @param tcp_keepcnt
#   Unanswered probes before the connection is dropped.
#
# @param metrics_enabled
#   Enable the Prometheus metrics endpoint at /metrics.
#   Uses xhttp_prom.so, which is included in the base kamailio package.
#
# @param ctl_enabled
#   Load ctl.so, which gives kamcmd its control socket.  kamailio cannot
#   reload its routing script, so kamailio.cfg changes still restart the
#   service, but a tls.cfg change becomes a `kamcmd tls.reload`: it re-reads
#   tls.cfg and the certificate files it names for new connections and
#   leaves established ones alone.  The refresh-only
#   Exec['scaip_proxy tls.reload'] can also be notified from outside, e.g.
#   by the resource that renews the certificate; it exists only with
#   manage_service, tls_enabled and ctl_enabled all true.  Turning ctl on
#   (or off) is itself a restart.
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
  $sip_domain       = $scaip_proxy::params::sip_domain,
  $upstream_host    = $scaip_proxy::params::upstream_host,
  $upstream_port    = $scaip_proxy::params::upstream_port,
  $upstream_scheme  = $scaip_proxy::params::upstream_scheme,
  Array[Stdlib::IP::Address::V4::Nosubnet] $upstream_addresses = $scaip_proxy::params::upstream_addresses,
  $tls_enabled      = $scaip_proxy::params::tls_enabled,
  $tls_cert_file    = $scaip_proxy::params::tls_cert_file,
  $tls_key_file     = $scaip_proxy::params::tls_key_file,
  $tls_ca_file      = $scaip_proxy::params::tls_ca_file,
  $children         = $scaip_proxy::params::children,
  $shm_mem_size     = $scaip_proxy::params::shm_mem_size,
  $debug_level      = $scaip_proxy::params::debug_level,
  $log_facility     = $scaip_proxy::params::log_facility,
  $http_port        = $scaip_proxy::params::http_port,
  Optional[Stdlib::IP::Address::V4::Nosubnet] $http_listen_address = undef,
  Boolean $tcp_keepalive = $scaip_proxy::params::tcp_keepalive,
  Integer[1] $tcp_keepidle = $scaip_proxy::params::tcp_keepidle,
  Integer[1] $tcp_keepintvl = $scaip_proxy::params::tcp_keepintvl,
  Integer[1] $tcp_keepcnt = $scaip_proxy::params::tcp_keepcnt,
  $metrics_enabled  = $scaip_proxy::params::metrics_enabled,
  Boolean $ctl_enabled = $scaip_proxy::params::ctl_enabled,
  $extra_packages   = $scaip_proxy::params::extra_packages,
) inherits scaip_proxy::params {

  if $upstream_host == undef {
    fail('scaip_proxy: upstream_host is required — set it via Hiera or as a class parameter')
  }

  $_http_listen_address = pick($http_listen_address, $listen_address)

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

    $_tls_reload = $ctl_enabled and $tls_enabled
    if $_tls_reload {
      exec { 'scaip_proxy tls.reload':
        command     => 'kamcmd tls.reload',
        path        => ['/usr/sbin', '/usr/bin', '/sbin', '/bin'],
        refreshonly => true,
        # no control socket (stopped, or started before ctl.so): nothing
        # to reload, and a failing kamcmd would fail the run
        onlyif      => 'kamcmd core.version',
        require     => Service['kamailio'],
      }
    }

    if $manage_config {
      File['/etc/kamailio/kamailio.cfg'] ~> Service['kamailio']
      File['/etc/default/kamailio']      ~> Service['kamailio']
      if $_tls_reload {
        File['/etc/kamailio/tls.cfg'] ~> Exec['scaip_proxy tls.reload']
      } else {
        File['/etc/kamailio/tls.cfg'] ~> Service['kamailio']
      }
    }

    Package[$all_packages] -> Service['kamailio']
  }
}

# vim: set et sw=2:

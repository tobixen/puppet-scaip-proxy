# == Class kamailio::params
# Default parameter values for the kamailio class.
class scaip_proxy::params {
  $package_ensure   = 'installed'

  # Set to true to manage the official Kamailio apt repository.
  # Version string appended to the repo URL: '60' -> kamailio60 (6.0.x).
  $manage_repo      = true
  $kamailio_version = '60'

  $manage_config    = true
  $manage_service   = true
  $service_enable   = true
  $service_ensure   = 'running'

  # IP address Kamailio listens on. '0.0.0.0' = all interfaces.
  # For production, restrict to the internal interface IP.
  $listen_address  = '0.0.0.0'
  $listen_port     = 5060
  $listen_tls_port = 5061

  # Public IP used to rewrite Contact/Via headers for NAT.
  # Must be set explicitly via Hiera for each server.
  $public_ip = $facts['networking']['ip']

  # Upstream SCAIP server — mandatory, no default
  $upstream_host   = undef
  $upstream_port   = 5061
  $upstream_scheme = 'sips'

  $tls_enabled  = true
  $tls_cert_file = '/etc/kamailio/tls/cert.pem'
  $tls_key_file  = '/etc/kamailio/tls/key.pem'
  $tls_ca_file   = undef

  $children     = 4
  $shm_mem_size = 64
  $debug_level  = 2
  $log_facility = 'LOG_LOCAL0'

  # HTTP port for /health, /ready, and /metrics endpoints
  $http_port       = 8080
  $metrics_enabled = true

  # Additional kamailio-* packages to install beyond the base set
  $extra_packages = []
}

# vim: set et sw=2:

require 'spec_helper'

describe 'scaip_proxy' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) { os_facts }

      context 'without upstream_host' do
        it { is_expected.to compile.and_raise_error(/upstream_host is required/) }
      end

      context 'with default parameters' do
        let(:params) { { upstream_host: 'sip.example.com' } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_class('scaip_proxy') }
        it { is_expected.to contain_class('scaip_proxy::params') }

        # Default: manage_repo=true, so apt::source should be present
        it { is_expected.to contain_apt__source('kamailio') }

        # Base + TLS packages (tls_enabled=true by default)
        it { is_expected.to contain_package('kamailio').with_ensure('installed') }
        it { is_expected.to contain_package('kamailio-tls-modules').with_ensure('installed') }
        # xhttp_prom is in the base kamailio package; no extra package needed for metrics
        it { is_expected.not_to contain_package('kamailio-extra-modules') }
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(/xhttp_prom/)
            .with_content(/prom_dispatch/)
        end

        # Config files
        it { is_expected.to contain_file('/etc/kamailio/kamailio.cfg').with_ensure('file') }
        it { is_expected.to contain_file('/etc/kamailio/tls.cfg').with_ensure('file') }
        it { is_expected.to contain_file('/etc/default/kamailio').with_ensure('file') }
        it { is_expected.to contain_file('/etc/kamailio/tls').with_ensure('directory') }

        # Service
        it { is_expected.to contain_service('kamailio').with_ensure('running') }
        it { is_expected.to contain_service('kamailio').with_enable(true) }

        # Config changes should notify the service
        it { is_expected.to contain_file('/etc/kamailio/kamailio.cfg').that_notifies('Service[kamailio]') }
        # tls.cfg is reloaded through ctl.so instead: a restart drops every
        # device connection, tls.reload only affects new ones.
        it { is_expected.to contain_file('/etc/kamailio/tls.cfg').that_notifies('Exec[scaip_proxy tls.reload]') }
        it { is_expected.not_to contain_file('/etc/kamailio/tls.cfg').that_notifies('Service[kamailio]') }
        it { is_expected.to contain_file('/etc/default/kamailio').that_notifies('Service[kamailio]') }
      end

      context 'with manage_repo => false' do
        let(:params) { { upstream_host: 'sip.example.com', manage_repo: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_apt__source('kamailio') }
        it { is_expected.to contain_package('kamailio') }
      end

      context 'with tls_enabled => false' do
        let(:params) { { upstream_host: 'sip.example.com', tls_enabled: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('kamailio') }
        it { is_expected.not_to contain_package('kamailio-tls-modules') }
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .without_content(/enable_tls/)
        end
      end

      # Without xhttp_prom_stats (or prom_counter/prom_gauge definitions)
      # /metrics answers "NO User defined metrics" - empty.
      context 'metrics_stats' do
        context 'by default' do
          let(:params) { { upstream_host: 'sip.example.com' } }

          it 'exports all internal statistics' do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^modparam\("xhttp_prom", "xhttp_prom_stats", "all"\)$})
          end
        end

        context 'narrowed' do
          let(:params) { { upstream_host: 'sip.example.com', metrics_stats: 'tm:' } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^modparam\("xhttp_prom", "xhttp_prom_stats", "tm:"\)$})
          end
        end

        context 'empty' do
          let(:params) { { upstream_host: 'sip.example.com', metrics_stats: '' } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .without_content(%r{xhttp_prom_stats})
          end
        end

        # It goes inside a quoted modparam; a quote or a newline would break
        # kamailio.cfg, and the restart that follows leaves kamailio dead.
        context 'with a quote in it' do
          let(:params) { { upstream_host: 'sip.example.com', metrics_stats: 'all")' } }

          it { is_expected.to compile.and_raise_error(%r{metrics_stats}) }
        end
      end

      context 'with metrics_enabled => false' do
        let(:params) { { upstream_host: 'sip.example.com', metrics_enabled: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('kamailio-extra-modules') }
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .without_content(/xhttp_prom/)
        end
      end

      # HTTP GET requests carry no Content-Length, which kamailio's TCP
      # reader otherwise rejects - it closes the connection without a reply,
      # so /health, /ready and /metrics all look dead to any ordinary HTTP
      # client.  http_reply_parse is not needed for them (tested 2026-10-07:
      # all three answer and nothing is logged without it), and it would make
      # the SIP listeners accept HTTP status lines too.
      context 'xhttp core parameters' do
        let(:params) { { upstream_host: 'sip.example.com' } }

        it 'accepts TCP messages without a Content-Length header' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{^tcp_accept_no_cl=yes$})
        end

        it 'does not set http_reply_parse' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .without_content(%r{^\s*http_reply_(parse|hack)\s*=})
        end
      end

      # The upstream holds idle TLS connections open for minutes.
      # TCP_USER_TIMEOUT only covers unacknowledged data, so a path that
      # dies while idle is found by the next alarm, 10 s late.  Keepalive
      # probes find it first.
      context 'tcp keepalive' do
        let(:params) { { upstream_host: 'sip.example.com' } }

        # kamailio's own default is tcp_keepalive=yes; what the module adds
        # is timers short enough to matter (the kernel waits 7200 s).
        it 'is on, with short timers, by default' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{^tcp_keepalive=yes$})
            .with_content(%r{^tcp_keepidle=60$})
            .with_content(%r{^tcp_keepintvl=10$})
            .with_content(%r{^tcp_keepcnt=3$})
        end

        context 'tuned' do
          let(:params) { { upstream_host: 'sip.example.com', tcp_keepidle: 120, tcp_keepintvl: 5, tcp_keepcnt: 4 } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^tcp_keepidle=120$})
              .with_content(%r{^tcp_keepintvl=5$})
              .with_content(%r{^tcp_keepcnt=4$})
          end
        end

        context 'off' do
          let(:params) { { upstream_host: 'sip.example.com', tcp_keepalive: false } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^tcp_keepalive=no$})
              .without_content(%r{^tcp_keepidle=})
          end
        end
      end

      # /health, /ready and /metrics are plain http and unauthenticated;
      # they need not sit on a routed address.
      context 'http_listen_address' do
        context 'by default' do
          let(:params) { { upstream_host: 'sip.example.com', listen_address: '192.0.2.10' } }

          it 'follows listen_address' do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^listen=tcp:192\.0\.2\.10:8080$})
          end
        end

        context 'set' do
          let(:params) { { upstream_host: 'sip.example.com', listen_address: '192.0.2.10', http_listen_address: '127.0.0.1' } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^listen=tcp:127\.0\.0\.1:8080$})
              .without_content(%r{^listen=tcp:192\.0\.2\.10:8080$})
          end
        end
      end

      # The upstream sends its status MESSAGE back over our own upstream
      # connection, with an R-URI naming our socket - so uri==myself is
      # true and the old test relayed it straight back upstream.  With the
      # upstream's addresses known, requests from them are answered and
      # logged, and never relayed.
      # Both are matched and rendered as IPv4 only: $si is compared as a
      # string, and listen= takes no brackets.
      context 'IPv6 addresses' do
        context 'in upstream_addresses' do
          let(:params) { { upstream_host: 'sip.example.com', upstream_addresses: ['2001:db8::1'] } }

          it { is_expected.to compile.and_raise_error(/upstream_addresses/) }
        end

        context 'in http_listen_address' do
          let(:params) { { upstream_host: 'sip.example.com', http_listen_address: '::1' } }

          it { is_expected.to compile.and_raise_error(/http_listen_address/) }
        end
      end

      context 'upstream_addresses' do
        context 'unset' do
          let(:params) { { upstream_host: 'sip.example.com' } }

          it do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .without_content(%r{route\(FROM_UPSTREAM\)})
          end
        end

        context 'set' do
          let(:params) { { upstream_host: 'sip.example.com', upstream_addresses: ['203.0.113.1', '203.0.113.2'] } }

          # Only requests the upstream addresses to the proxy itself (the
          # status names our socket).  One it addresses to a device alias
          # must still reach the device branch.
          it 'absorbs only upstream requests addressed to the proxy, before the device branch' do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^    if \(\(\$si == "203\.0\.113\.1" \|\| \$si == "203\.0\.113\.2"\) && uri==myself\) \{\n        route\(FROM_UPSTREAM\);\n    \}\n(?:.*\n)*?    if \(uri==myself\) \{$})
          end

          it 'answers and logs, relaying nothing' do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{route\[FROM_UPSTREAM\] \{\s*xlog\("L_INFO", "Status from \$si[^\n]*\$ci[^\n]*\);\s*sl_send_reply\("200", "OK"\);\s*exit;\s*\}}m)
          end
        end
      end

      # ctl.so gives kamcmd a control socket.  kamailio cannot reload its
      # routing script, but tls.reload re-reads tls.cfg and the certificate
      # files it names, for new connections, without dropping existing ones.
      context 'ctl' do
        context 'by default' do
          let(:params) { { upstream_host: 'sip.example.com' } }

          it 'loads ctl.so' do
            is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
              .with_content(%r{^loadmodule "ctl\.so"$})
          end

          it 'reloads TLS on refresh only, after the service' do
            is_expected.to contain_exec('scaip_proxy tls.reload')
              .with_command('kamcmd tls.reload')
              .with_refreshonly(true)
              .that_requires('Service[kamailio]')
          end

          # A stopped kamailio, or one started before ctl.so was loaded, has
          # no control socket; there is nothing to reload, and a failed
          # kamcmd would fail the run.
          it 'skips the reload when kamailio does not answer' do
            is_expected.to contain_exec('scaip_proxy tls.reload')
              .with_onlyif('kamcmd core.version')
          end
        end

        context 'disabled' do
          let(:params) { { upstream_host: 'sip.example.com', ctl_enabled: false } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to contain_file('/etc/kamailio/kamailio.cfg').without_content(%r{ctl\.so}) }
          it { is_expected.not_to contain_exec('scaip_proxy tls.reload') }
          it { is_expected.to contain_file('/etc/kamailio/tls.cfg').that_notifies('Service[kamailio]') }
        end

        context 'without TLS' do
          let(:params) { { upstream_host: 'sip.example.com', tls_enabled: false } }

          it { is_expected.to compile.with_all_deps }
          it { is_expected.not_to contain_exec('scaip_proxy tls.reload') }
        end
      end

      context 'with manage_service => false' do
        let(:params) { { upstream_host: 'sip.example.com', manage_service: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('kamailio') }
        it { is_expected.not_to contain_exec('scaip_proxy tls.reload') }
      end

      context 'with manage_config => false' do
        let(:params) { { upstream_host: 'sip.example.com', manage_config: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_file('/etc/kamailio/kamailio.cfg') }
      end

      context 'with extra_packages' do
        let(:params) { { upstream_host: 'sip.example.com', extra_packages: ['kamailio-utils-modules'] } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to contain_package('kamailio-utils-modules') }
      end

      context 'with custom upstream' do
        let(:params) do
          {
            upstream_host:   'sip.example.com',
            upstream_port:   5061,
            upstream_scheme: 'sips',
            public_ip:       '203.0.113.1',
          }
        end

        it { is_expected.to compile.with_all_deps }
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{sip\.example\.com})
        end
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{alias=203\.0\.113\.1})
        end
      end

      context 'with sip_domain' do
        let(:params) { { upstream_host: 'sip.example.com', sip_domain: 'proxy.example.com' } }

        it 'emits the sip_domain as a kamailio alias' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{^alias=proxy\.example\.com$})
        end
      end

      context 'directional routing' do
        let(:params) { { upstream_host: 'sip.example.com' } }

        it 'routes to UPSTREAM only when uri==myself' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{uri==myself\b.*route\(UPSTREAM\)}m)
        end

        it 'calls handle_ruri_alias for inbound requests from upstream' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{handle_ruri_alias})
        end

        it 'adds a contact alias for devices that omit the Contact header' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{add_contact_alias})
        end
      end

      context 'Request-URI and To header rewriting' do
        let(:params) { { upstream_host: 'sip.example.com' } }

        # The upstream rejects requests with the proxy hostname in the Request-URI
        # and To header; both must be rewritten to upstream_host before forwarding.
        it 'rewrites the Request-URI domain to the upstream host' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{\$rd\s*=\s*"sip\.example\.com"})
        end

        it 'removes the original To header' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{remove_hf\("To"\)})
        end

        it 'appends a rewritten To header with the upstream host' do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .with_content(%r{append_hf\("To:.*sip\.example\.com})
        end
      end
    end
  end
end

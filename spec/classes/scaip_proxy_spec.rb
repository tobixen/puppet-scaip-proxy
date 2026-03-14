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
        # metrics_enabled=true by default
        it { is_expected.to contain_package('kamailio-extra-modules').with_ensure('installed') }

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
        it { is_expected.to contain_file('/etc/kamailio/tls.cfg').that_notifies('Service[kamailio]') }
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

      context 'with metrics_enabled => false' do
        let(:params) { { upstream_host: 'sip.example.com', metrics_enabled: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_package('kamailio-extra-modules') }
        it do
          is_expected.to contain_file('/etc/kamailio/kamailio.cfg')
            .without_content(/prometheus/)
        end
      end

      context 'with manage_service => false' do
        let(:params) { { upstream_host: 'sip.example.com', manage_service: false } }

        it { is_expected.to compile.with_all_deps }
        it { is_expected.not_to contain_service('kamailio') }
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
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/monadic/utils/ssl_configuration'

RSpec.describe Monadic::Utils::SSLConfiguration do
  around do |example|
    Dir.mktmpdir('ssl-config-spec') do |dir|
      @ca = File.join(dir, 'ca.pem')
      File.write(@ca, "not a real certificate\n")
      example.run
    end
  end

  # configure! sets the process-wide HTTP defaults; those made here point at
  # a CA file that is gone after the example, so the suite's are put back.
  around do |example|
    defaults = HTTP.default_options
    example.run
  ensure
    HTTP.default_options = defaults
    described_class.instance_variable_set(:@params, nil)
  end

  it 'leaves OpenSSL\'s own defaults as they are, and keeps its own copy with CRL checks off and the CA file given' do
    before = OpenSSL::SSL::SSLContext::DEFAULT_PARAMS.dup
    expect(described_class).not_to receive(:log).with(/SSL configuration failed/, anything)

    described_class.configure!('SSL_CERT_FILE' => @ca)

    expect(OpenSSL::SSL::SSLContext::DEFAULT_PARAMS).to eq(before)
    expect(described_class.params[:ca_file]).to eq(@ca)
    flags = described_class.params[:verify_flags]
    expect(flags & OpenSSL::X509::V_FLAG_CRL_CHECK).to eq(0) if flags && defined?(OpenSSL::X509::V_FLAG_CRL_CHECK)
  end

  it 'gives the http gem and Net::HTTP contexts made from its own copy' do
    described_class.configure!('SSL_CERT_FILE' => @ca)

    expect(HTTP.default_options.ssl_context.verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
    http = Net::HTTP.new('example.invalid', 443)
    http.use_ssl = true
    allow(http).to receive(:original_start)
    http.start
    expect(http.instance_variable_get(:@ssl_context).verify_mode).to eq(OpenSSL::SSL::VERIFY_PEER)
  end
end

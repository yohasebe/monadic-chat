# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/monadic/utils/http_client'

# The http gem has no default timeout, so a silent peer parks the calling
# thread forever. These examples pin the two properties that make the helper
# safe, both of which are easy to lose in a refactor:
#
#   1. per-operation form (never a bare Numeric, which caps the WHOLE request
#      and would abort healthy long streams)
#   2. an explicit write timeout (PerOperation defaults omitted values to
#      0.25s, which would break large uploads)
RSpec.describe Monadic::Utils::HttpClient do
  BUILDERS = %i[rest generation streaming download].freeze

  def timeout_options_for(client)
    client.default_options.timeout_options
  end

  def timeout_class_for(client)
    client.default_options.timeout_class
  end

  BUILDERS.each do |builder|
    describe ".#{builder}" do
      let(:client) { described_class.public_send(builder) }

      it 'uses the per-operation timeout class, not the global one' do
        expect(timeout_class_for(client)).to eq(HTTP::Timeout::PerOperation)
      end

      it 'sets connect, read, and write explicitly' do
        opts = timeout_options_for(client)
        expect(opts).to include(:connect_timeout, :read_timeout, :write_timeout)
      end

      it 'never leaves a timeout at the gem default of 0.25s' do
        timeout_options_for(client).each_value do |v|
          expect(v).to be > 1
        end
      end

      it 'accepts per-call overrides' do
        custom = described_class.public_send(builder, connect: 7, read: 8, write: 9)
        expect(timeout_options_for(custom)).to include(
          connect_timeout: 7, read_timeout: 8, write_timeout: 9
        )
      end
    end
  end

  it 'gives a non-streaming generation call enough read budget for a slow model' do
    # For a one-shot request the server stays silent until the answer is ready,
    # so read must cover the model's whole thinking time — not just a chunk gap.
    expect(timeout_options_for(described_class.generation)[:read_timeout])
      .to be >= 600
  end

  it 'keeps the streaming read timeout as a silence budget, not a total cap' do
    expect(timeout_class_for(described_class.streaming)).to eq(HTTP::Timeout::PerOperation)
    expect(timeout_options_for(described_class.streaming)[:read_timeout]).to be >= 120
  end

  it 'returns a chainable client' do
    expect(described_class.rest.headers('X-Test' => '1')).to be_a(HTTP::Client)
  end
end

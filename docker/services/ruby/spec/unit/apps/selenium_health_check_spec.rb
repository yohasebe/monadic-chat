# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require_relative '../../../apps/mermaid_grapher/mermaid_grapher_tools'
require_relative '../../../apps/drawio_grapher/drawio_grapher_tools'

RSpec.describe "Selenium service health check" do
  # Test both modules share the same pattern
  [MermaidGrapherTools, DrawIOGrapher].each do |mod|
    context mod.name do
      let(:instance) do
        Class.new { include mod }.new
      end

      describe "#selenium_service_reachable?" do
        it "returns true when Selenium responds with 200" do
          response = instance_double(Net::HTTPOK)
          allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)

          allow(Net::HTTP).to receive(:start).and_yield(
            instance_double(Net::HTTP, get: response)
          )

          expect(instance.send(:selenium_service_reachable?)).to be true
        end

        it "returns false on connection refused" do
          allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

          expect(instance.send(:selenium_service_reachable?)).to be false
        end

        it "returns false on timeout" do
          allow(Net::HTTP).to receive(:start).and_raise(Net::OpenTimeout)

          expect(instance.send(:selenium_service_reachable?)).to be false
        end

        it "returns false on DNS resolution failure" do
          allow(Net::HTTP).to receive(:start).and_raise(SocketError.new("getaddrinfo: Name or service not known"))

          expect(instance.send(:selenium_service_reachable?)).to be false
        end
      end

      describe "##{mod.name.include?('Mermaid') ? 'mermaid' : 'drawio'}_session_active?" do
        let(:shared_volume) { Dir.mktmpdir }
        let(:session_file) { File.join(shared_volume, ".browser_session_id") }

        before do
          allow(Monadic::Utils::Environment).to receive(:shared_volume).and_return(shared_volume)
        end

        after { FileUtils.rm_rf(shared_volume) }

        let(:method_name) { mod.name.include?("Mermaid") ? :mermaid_session_active? : :drawio_session_active? }

        it "returns false when session file does not exist" do
          expect(instance.send(method_name)).to be false
        end

        it "returns false when session file is empty" do
          File.write(session_file, "")
          expect(instance.send(method_name)).to be false
        end

        it "returns true when session file exists and Selenium is reachable" do
          File.write(session_file, "abc123")
          allow(instance).to receive(:selenium_service_reachable?).and_return(true)

          expect(instance.send(method_name)).to be true
        end

        it "returns false and cleans up when Selenium is unreachable" do
          File.write(session_file, "abc123")
          allow(instance).to receive(:selenium_service_reachable?).and_return(false)

          expect(instance.send(method_name)).to be false
          expect(File.exist?(session_file)).to be false
        end
      end
    end
  end
end

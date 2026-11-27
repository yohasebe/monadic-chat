# frozen_string_literal: true

require_relative "../../spec_helper"
require_relative "../../../lib/monadic/utils/public_address"

RSpec.describe Monadic::Utils::PublicAddress do
  def check(host, addresses = ["93.184.216.34"])
    described_class.check!(host, resolver: ->(_name) { addresses })
  end

  it "takes a name whose addresses are all public, and a public address" do
    expect(check("example.com", ["93.184.216.34", "2606:2800:220:1::1"])).to eq(["93.184.216.34", "2606:2800:220:1::1"])
    expect(check("8.8.8.8")).to eq(["8.8.8.8"])
  end

  it "refuses loopback, private, link-local, shared and unspecified addresses, as written or resolved" do
    %w[127.0.0.1 10.0.0.1 172.16.5.4 192.168.1.1 169.254.169.254 100.64.0.1 0.0.0.0 ::1 [::1] fe80::1 fd12::1
       ::ffff:10.0.0.1].each do |address|
      expect { check(address) }.to raise_error(described_class::Refused), address
    end
    expect { check("example.com", ["93.184.216.34", "10.0.0.5"]) }.to raise_error(described_class::Refused)
  end

  it "refuses the names of this machine and of the Docker host, and a name that does not resolve" do
    %w[localhost LOCALHOST. app.localhost host.docker.internal gateway.docker.internal].each do |name|
      expect { check(name) }.to raise_error(described_class::Refused), name
    end
    expect { check("nowhere.example", []) }.to raise_error(described_class::Refused)
    expect { check("") }.to raise_error(described_class::Refused)
  end
end

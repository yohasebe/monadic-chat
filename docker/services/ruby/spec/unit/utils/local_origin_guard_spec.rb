# frozen_string_literal: true

require "spec_helper"
require "rack/mock_request"
require_relative "../../../lib/monadic/utils/local_origin_guard"

RSpec.describe Monadic::Utils::LocalOriginGuard do
  let(:reached) { [] }
  let(:downstream) { ->(env) { reached << env; [200, {}, ["ok"]] } }

  def call(guard, method: "POST", host: "localhost:4567", origin: nil, upgrade: false)
    env = Rack::MockRequest.env_for("http://localhost:4567/", method: method)
    host ? env["HTTP_HOST"] = host : env.delete("HTTP_HOST")
    env["HTTP_ORIGIN"] = origin if origin
    if upgrade
      env["HTTP_UPGRADE"] = "websocket"
      env["HTTP_CONNECTION"] = "Upgrade"
    end
    guard.call(env).first
  end

  describe "mode :web" do
    let(:guard) { described_class.new(downstream) }

    it "lets this computer's own pages change things" do
      %w[http://localhost:4567 http://127.0.0.1:4567 http://LOCALHOST:4567].each do |origin|
        host = origin.sub("http://", "")
        expect(call(guard, host: host, origin: origin)).to eq(200), origin
      end
      expect(call(guard, host: "[::1]:4567", origin: "http://[::1]:4567")).to eq(200)
    end

    it "lets requests without an Origin through (not a browser page)" do
      expect(call(guard)).to eq(200)
      expect(call(guard, upgrade: true, method: "GET")).to eq(200)
    end

    it "refuses changes and WebSocket upgrades from other sites" do
      [
        "http://evil.example",
        "https://localhost:4567",      # another scheme is another origin
        "http://localhost:8080",       # another local server is another origin
        "http://localhost.evil.example:4567",
        "http://user@localhost:4567",
        "null",
        "not a url",
        "http://localhost:4567/path",
        "http://localhost:4567?x=1",
        "http://localhost:4567#x"
      ].each do |origin|
        expect(call(guard, origin: origin)).to eq(403), "POST #{origin}"
        expect(call(guard, method: "GET", origin: origin, upgrade: true)).to eq(403), "WS #{origin}"
        %w[PUT PATCH DELETE].each { |m| expect(call(guard, method: m, origin: origin)).to eq(403), "#{m} #{origin}" }
      end
      expect(reached).to be_empty
    end

    it "leaves plain reads alone, whatever the Origin" do
      expect(call(guard, method: "GET", origin: "http://evil.example")).to eq(200)
    end

    it "refuses any request naming another host, even a read (DNS rebinding)" do
      ["evil.example:4567", "evil.example", "192.168.1.5:4567", "localhost.evil.example:4567", "local host:4567",
       "localhost.:4567", "0.0.0.0:4567", "::1:4567"].each do |host|
        expect(call(guard, method: "GET", host: host)).to eq(403), host
      end
      [nil, ""].each { |host| expect(call(guard, method: "GET", host: host)).to eq(403), host.inspect }
      # A rebinding page sends its own name as both Host and Origin.
      expect(call(guard, host: "evil.example:4567", origin: "http://evil.example:4567")).to eq(403)
      expect(reached).to be_empty
    end

    it "answers refusals with a reason and no details of the request" do
      env = Rack::MockRequest.env_for("http://localhost:4567/", method: "POST", "HTTP_HOST" => "localhost:4567", "HTTP_ORIGIN" => "http://evil.example")
      status, headers, body = guard.call(env)
      expect(status).to eq(403)
      expect(headers["content-type"]).to eq("application/json")
      expect(JSON.parse(body.join)).to include("reason" => "origin_not_local")
      expect(body.join).not_to include("evil.example")
    end
  end

  describe "mode :api" do
    let(:guard) { described_class.new(downstream, mode: :api) }

    it "refuses every request that carries an Origin, local or not, on every method" do
      %w[http://evil.example http://localhost:4567 http://127.0.0.1:3100 null].each do |origin|
        %w[GET POST OPTIONS].each do |m|
          expect(call(guard, method: m, host: "127.0.0.1:3100", origin: origin)).to eq(403), "#{m} #{origin}"
        end
      end
      expect(reached).to be_empty
    end

    it "serves programs (no Origin) that name this computer" do
      expect(call(guard, host: "127.0.0.1:3100")).to eq(200)
      expect(call(guard, host: "evil.example:3100")).to eq(403)
    end
  end
end

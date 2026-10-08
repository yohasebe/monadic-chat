# frozen_string_literal: true

require_relative "../../../lib/monadic/utils/server_mode"
require_relative "../../../lib/monadic/utils/auth_middleware"
require "rack"

# The server runs standalone. A server setting left in the env file must not
# switch on the access check, which would lock the desktop app out.
RSpec.describe Monadic::Utils::ServerMode do
  it "turns a server setting off and says so" do
    config = { "DISTRIBUTED_MODE" => "server" }
    expect(described_class.normalize!(config)).to be true
    expect(config["DISTRIBUTED_MODE"]).to eq("off")
  end

  it "leaves standalone as it is" do
    config = { "DISTRIBUTED_MODE" => "off" }
    expect(described_class.normalize!(config)).to be false
    expect(config["DISTRIBUTED_MODE"]).to eq("off")
  end

  it "lets the auth middleware pass a non-loopback client once normalized" do
    config = { "DISTRIBUTED_MODE" => "server", "MONADIC_AUTH_TOKEN" => "t" }
    described_class.normalize!(config)
    stub_const("CONFIG", config)
    app = Monadic::Utils::AuthMiddleware.new(->(_env) { [200, { "content-type" => "text/plain" }, ["ok"]] })
    env = Rack::MockRequest.env_for("http://example.org/")
    env["REMOTE_ADDR"] = "192.168.65.1"
    expect(Rack::Lint.new(app).call(env).first).to eq(200)
  end
end

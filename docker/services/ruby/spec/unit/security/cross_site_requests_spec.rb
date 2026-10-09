# frozen_string_literal: true

require "spec_helper"
require "json"
require "open3"
require "tmpdir"
require "rbconfig"

# The whole web app, booted from config.ru as the server boots it, asked how
# it treats requests a web page on the same computer could send. Booted in a
# child process with its own HOME, so nothing of the user's config, data or
# keys is read and the specs' own stubs do not shape the answers.
RSpec.describe "Web app and requests from other sites" do
  # Methods, not constants: a constant here would be defined on Object and
  # collide with other specs' constants of the same name.
  def app_root
    File.expand_path("../../..", __dir__)
  end

  def probe_script
    <<~'RUBY'
    require "rack"
    require "rack/mock_request"
    require "json"
    app, = Rack::Builder.parse_file("config.ru")
    req = Rack::MockRequest.new(app)
    data = File.join(Dir.home, "monadic", "data")
    form = lambda do |field, name, body|
      "--B\r\nContent-Disposition: form-data; name=\"#{field}\"; filename=\"#{name}\"\r\n" \
        "Content-Type: application/octet-stream\r\n\r\n#{body}\r\n--B--\r\n"
    end
    upload = lambda do |name, headers, path: "/upload_audio", field: "audioFile"|
      env = { input: form.call(field, name, "ID3"), "CONTENT_TYPE" => "multipart/form-data; boundary=B",
              "HTTP_HOST" => "localhost:4567" }.merge(headers)
      status = req.post("http://localhost:4567#{path}", env).status
      { "status" => status, "written" => File.exist?(File.join(data, name)) }
    end
    ws = lambda do |headers|
      env = { "HTTP_HOST" => "localhost:4567", "HTTP_UPGRADE" => "websocket", "HTTP_CONNECTION" => "Upgrade",
              "HTTP_SEC_WEBSOCKET_VERSION" => "13", "HTTP_SEC_WEBSOCKET_KEY" => "dGhlIHNhbXBsZSBub25jZQ==" }.merge(headers)
      begin
        req.get("http://localhost:4567/", env).status
      rescue StandardError => e
        "raised #{e.class}" # reached the WebSocket handler, which needs a real socket
      end
    end
    out = {
      "upload_other_site" => upload.call("a.mp3", { "HTTP_ORIGIN" => "http://evil.example" }),
      "upload_null_origin" => upload.call("b.mp3", { "HTTP_ORIGIN" => "null" }),
      "upload_rebinding" => upload.call("c.mp3", { "HTTP_HOST" => "evil.example:4567", "HTTP_ORIGIN" => "http://evil.example:4567" }),
      "upload_own_page" => upload.call("d.mp3", { "HTTP_ORIGIN" => "http://localhost:4567" }),
      "upload_no_origin" => upload.call("e.mp3", {}),
      "document_other_site" => upload.call("f.txt", { "HTTP_ORIGIN" => "http://evil.example" }, path: "/document", field: "docFile"),
      "ws_other_site" => ws.call({ "HTTP_ORIGIN" => "http://evil.example" }),
      "ws_null_origin" => ws.call({ "HTTP_ORIGIN" => "null" }),
      "ws_own_page" => ws.call({ "HTTP_ORIGIN" => "http://localhost:4567" }),
      "read_other_host" => req.get("http://localhost:4567/", "HTTP_HOST" => "evil.example:4567").status,
      "read_own_host" => req.get("http://localhost:4567/", "HTTP_HOST" => "localhost:4567").status,
      "protection_reaction" => Sinatra::Application.protection[:reaction].to_s
    }

    # Documents in the shared folder that can run scripts are served in a
    # sandbox of their own origin, under every name the folder is served by.
    { "page.html" => "<p>x</p>", "chart.svg" => "<svg xmlns='http://www.w3.org/2000/svg'/>", "photo.png" => "PNG", "doc.pdf" => "%PDF" }
      .each { |name, body| File.write(File.join(data, name), body) }
    served = lambda do |path|
      r = req.get("http://localhost:4567#{path}", "HTTP_HOST" => "localhost:4567")
      { "status" => r.status, "csp" => r.headers["content-security-policy"], "nosniff" => r.headers["x-content-type-options"] }
    end
    out["serve_html"] = served.call("/data/page.html")
    out["serve_html_alias"] = served.call("/monadic/data/page.html")
    out["serve_svg"] = served.call("/data/chart.svg")
    out["serve_png"] = served.call("/data/photo.png")
    out["serve_pdf"] = served.call("/data/doc.pdf")
    out["serve_root_redirect"] = req.get("http://localhost:4567/page.html", "HTTP_HOST" => "localhost:4567").headers["location"].to_s

    # WebSockets over a real socket: the own page must actually connect and
    # receive the first message, not merely avoid a 403.
    require "async"
    require "async/http/endpoint"
    require "async/http/server"
    require "async/websocket/client"
    require "protocol/rack"
    require "socket"
    port = (probe = TCPServer.new("127.0.0.1", 0)).addr[1]
    probe.close
    endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}")
    Async do |task|
      server = task.async { Async::HTTP::Server.new(Protocol::Rack::Adapter.new(app), endpoint).run }
      task.sleep(0.2)
      connect = lambda do |origin|
        client_endpoint = Async::HTTP::Endpoint.parse("http://127.0.0.1:#{port}/?tab_id=probe-#{rand(1_000_000)}")
        Async::WebSocket::Client.connect(client_endpoint, headers: [["origin", origin]]) do |conn|
          message = task.with_timeout(10) { conn.read }
          "connected:#{JSON.parse(message.to_str)["type"]}"
        end
      rescue Async::WebSocket::ConnectionError => e
        "refused:#{e.message[/\d{3}/] || "negotiation"}"
      rescue StandardError => e
        "error:#{e.class}"
      end
      out["ws_socket_own_page"] = connect.call("http://127.0.0.1:#{port}")
      out["ws_socket_other_site"] = connect.call("http://evil.example")
      out["ws_socket_null"] = connect.call("null")
      server.stop
    end
    STDOUT.puts "PROBE #{out.to_json}"
    STDOUT.flush
    exit!(0)
    RUBY
  end

  def probe
    Dir.mktmpdir("cross-site-home") do |home|
      env = { "HOME" => home, "IN_CONTAINER" => "false", "EXTRA_LOGGING" => nil }
      out, status = Open3.capture2e(env, RbConfig.ruby, "-e", probe_script, chdir: app_root)
      line = out.lines.find { |l| l.start_with?("PROBE ") }
      raise "probe failed (#{status.exitstatus}):\n#{out.lines.last(20).join}" unless line

      JSON.parse(line.delete_prefix("PROBE "))
    end
  end

  # One boot for all examples.
  before(:all) { @result = probe }

  it "refuses uploads from other sites, null origins and rebinding pages, and writes nothing" do
    %w[upload_other_site upload_null_origin upload_rebinding document_other_site].each do |key|
      expect(@result[key]).to eq({ "status" => 403, "written" => false }), key
    end
  end

  it "still takes uploads from its own page and from programs" do
    expect(@result["upload_own_page"]).to eq({ "status" => 200, "written" => true })
    expect(@result["upload_no_origin"]).to eq({ "status" => 200, "written" => true })
  end

  it "refuses WebSocket connections from other sites and lets its own page through" do
    expect(@result["ws_other_site"]).to eq(403)
    expect(@result["ws_null_origin"]).to eq(403)
    expect(@result["ws_own_page"]).not_to eq(403)
  end

  it "connects its own page over a real socket and refuses other sites" do
    expect(@result["ws_socket_own_page"]).to eq("connected:apps")
    expect(@result["ws_socket_other_site"]).to start_with("refused")
    expect(@result["ws_socket_null"]).to start_with("refused")
  end

  it "serves shared pages and SVGs sandboxed, and images and PDFs as they are" do
    %w[serve_html serve_html_alias serve_svg].each do |key|
      expect(@result[key]["status"]).to eq(200), key
      expect(@result[key]["csp"]).to start_with("sandbox allow-scripts"), key
      expect(@result[key]["csp"]).not_to include("allow-same-origin"), key
    end
    %w[serve_png serve_pdf].each do |key|
      expect(@result[key]).to include("status" => 200, "csp" => nil), key
    end
    %w[serve_html serve_png serve_pdf].each { |key| expect(@result[key]["nosniff"]).to eq("nosniff"), key }
    expect(@result["serve_root_redirect"]).to end_with("/data/page.html")
  end

  it "answers only requests naming this computer" do
    expect(@result["read_other_host"]).to eq(403)
    expect(@result["read_own_host"]).to eq(200)
  end

  it "has Rack::Protection refuse, not just drop the session" do
    expect(@result["protection_reaction"]).to eq("deny")
  end
end

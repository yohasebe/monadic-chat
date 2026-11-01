# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "uri"
require_relative "../../../lib/monadic/utils/secret_redactor"
require_relative "../../../lib/monadic/utils/error_formatter"
require_relative "../../../lib/monadic/utils/extra_logger"
require_relative "../../../lib/monadic/utils/segment_transcriber"

# Made-up values: none of them is a real credential.
FAKE_ANTHROPIC = "sk-ant-api03-FAKEFAKEFAKEFAKEFAKE0123456789"
FAKE_MISTRAL = "FakeMistralKey0123456789abcdef"
FAKE_TOKEN = "fake-token-value-123456"

RSpec.describe Monadic::Utils::SecretRedactor do
  before do
    stub_const("CONFIG", {
      "ANTHROPIC_API_KEY" => FAKE_ANTHROPIC,
      "MISTRAL_API_KEY" => FAKE_MISTRAL,
      "SOME_SERVICE_TOKEN" => FAKE_TOKEN,
      "SHORT_API_KEY" => "abc",
      "MODEL_NAME" => "a-model-name-that-is-long"
    })
  end

  describe ".redact" do
    it "replaces the values of secret settings, whatever their format" do
      out = described_class.redact("key #{FAKE_MISTRAL} and #{FAKE_TOKEN}")
      expect(out).not_to include(FAKE_MISTRAL)
      expect(out).not_to include(FAKE_TOKEN)
      expect(out).to eq("key [redacted] and [redacted]")
    end

    it "replaces a value whole, with no prefix or suffix left" do
      out = described_class.redact("x-api-key: #{FAKE_ANTHROPIC}")
      expect(out).not_to include("sk-ant")
      expect(out).not_to include(FAKE_ANTHROPIC[-4..])
    end

    it "replaces environment values with secret names" do
      ENV["SPEC_REDACTOR_API_KEY"] = "env-only-secret-0123456789"
      expect(described_class.redact("env-only-secret-0123456789")).to eq("[redacted]")
    ensure
      ENV.delete("SPEC_REDACTOR_API_KEY")
    end

    it "replaces 1Password references" do
      expect(described_class.redact("ref op://Private/OpenAI/credential end")).to eq("ref [redacted] end")
    end

    it "replaces key formats that are not in the settings" do
      [
        "sk-proj-AAAAAAAAAAAAAAAAAAAAAAAA",
        "sk_aaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "xai-AAAAAAAAAAAAAAAAAAAAAAAA",
        "AIzaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "gsk_AAAAAAAAAAAAAAAAAAAAAAAA",
        "tvly-AAAAAAAAAAAAAAAAAAAAAAAA",
        "Bearer AAAAAAAAAAAAAAAAAAAAAAAA"
      ].each do |text|
        expect(described_class.redact("v: #{text}")).not_to include(text.split.last), text
      end
    end

    it "replaces every part of a Digest credential" do
      out = described_class.redact('Authorization: Digest username="alice", nonce="abc123", response="0123456789abcdef"')
      %w[alice abc123 0123456789abcdef].each { |part| expect(out).not_to include(part) }
    end

    context "with a non-ASCII password" do
      let(:password) { "review92-pässword/+ \u{1D11E}x" }

      before { stub_const("CONFIG", { "SVC_PASSWORD" => password }) }

      it "replaces it in ASCII-only JSON (Python's json.dumps)" do
        json = JSON.generate({ "e" => password }, ascii_only: true)
        expect(JSON.parse(described_class.redact_values(json))["e"]).to eq("[redacted]")
      end

      it "replaces its percent-encoded forms" do
        form = URI.encode_www_form_component(password)
        [form, form.gsub("+", "%20"), form.gsub(/%[0-9A-F]{2}/, &:downcase)].each do |encoded|
          expect(described_class.redact_values("q=#{encoded}&n=1")).to eq("q=[redacted]&n=1")
        end
      end
    end

    it "replaces passwords in URLs" do
      expect(described_class.redact("https://bob:hunter2xyz@example.test/x")).to eq("https://bob:[redacted]@example.test/x")
      expect(described_class.redact("https://example.test/?password=abc12345&a=1")).to eq("https://example.test/?password=[redacted]&a=1")
      url = "https://example.test:443?email=alice@example.org"
      expect(described_class.redact(url)).to eq(url)
    end

    it "keeps binary or broken text and replaces known values in it" do
      broken = "ok \xFF #{FAKE_TOKEN} end".dup.force_encoding("UTF-8")
      out = described_class.redact_values(broken)
      expect(out.b).to eq("ok \xFF [redacted] end".b)
    end

    it "replaces the whole credential of other authorization schemes" do
      out = described_class.redact("authorization: Basic dXNlcjpwYXNzd29yZA== next")
      expect(out).not_to include("dXNlcjpwYXNz")
      out = described_class.redact("Authorization: Token abcdefghijklmnop1234")
      expect(out).not_to include("abcdefghijklmnop1234")
    end

    it "treats any value of a secret setting as secret, even a common word" do
      stub_const("CONFIG", { "SERVICE_PASSWORD" => "disabled" })
      expect(described_class.redact("password is disabled")).to eq("password is [redacted]")
    end

    it "leaves short values, other settings and ordinary text alone" do
      text = "abc uses a-model-name-that-is-long; task_runner done"
      expect(described_class.redact(text)).to eq(text)
    end

    it "returns nil for nil" do
      expect(described_class.redact(nil)).to be_nil
    end
  end

  describe ".redact_deep" do
    it "redacts strings inside hashes and arrays" do
      out = described_class.redact_deep({ content: [{ text: "key #{FAKE_MISTRAL}" }], n: 1 })
      expect(out).to eq({ content: [{ text: "key [redacted]" }], n: 1 })
    end

    it "replaces a known value inside a long base64-like string" do
      text = ("A" * 1024) + FAKE_MISTRAL
      expect(described_class.redact_deep({ text: text })[:text]).not_to include(FAKE_MISTRAL)
    end

    it "replaces known values and references in hash keys" do
      out = described_class.redact_deep({ FAKE_MISTRAL => "v", "op://Vault/Item/f" => 1, keep: 2 })
      expect(out.keys.map(&:to_s).join).not_to include(FAKE_MISTRAL)
      expect(out.keys.map(&:to_s).join).not_to include("op://")
      expect(out[:keep]).to eq(2)
    end

    it "leaves code, URLs and binary data that hold no known secret exactly as they are" do
      data = {
        code: "const options = { authorization: false };\nfetch('https://example.test/items?key=chapter1')",
        image: "AIzaAAAAAAAAAAAAAAAAAAAAAAAA" + ("QUJD" * 50),
        token_like: "sk-proj-AAAAAAAAAAAAAAAAAAAAAAAA"
      }
      expect(described_class.redact_deep(data)).to eq(data)
    end
  end

  describe "exits" do
    it "ErrorFormatter.scrub_identifiers also replaces secret values" do
      expect(Monadic::Utils::ErrorFormatter.scrub_identifiers("bad key #{FAKE_MISTRAL}")).to eq("bad key [redacted]")
    end

    it "a tool error sent back to the model carries no secret" do
      msg = Monadic::Utils::ErrorFormatter.tool_error(provider: "X", tool_name: "t", message: "401 #{FAKE_MISTRAL}")
      expect(msg).not_to include(FAKE_MISTRAL)
    end

    it "every formatted error carries no secret" do
      msg = Monadic::Utils::ErrorFormatter.api_error(provider: "X", message: "401 for #{FAKE_TOKEN}")
      expect(msg).not_to include(FAKE_TOKEN)
    end

    it "a failed command returns its error to the model without secrets" do
      require_relative "../../../lib/monadic/app"
      allow(Monadic::Utils::Environment).to receive(:rotate_log)
      allow(Open3).to receive(:capture3).and_return(["", "provider said #{FAKE_MISTRAL}", double(success?: false)])
      stub_const("MonadicApp::COMMAND_LOG_FILE", File.join(Dir.tmpdir, "spec-command-#{Process.pid}.log"))
      app = MonadicApp.new
      allow(app).to receive(:ruby_side_command).and_return({ argv: ["ruby", "x.rb"], chdir: Dir.tmpdir, path: "/usr/bin" })
      allow(app).to receive(:ruby_side_env).and_return({})
      out = app.send(:send_command, command: "x.rb", container: "ruby")
      expect(out).to start_with("Error occurred:")
      expect(out).not_to include(FAKE_MISTRAL)
    ensure
      FileUtils.rm_f(File.join(Dir.tmpdir, "spec-command-#{Process.pid}.log"))
    end

    it "degradation notices carry no secret" do
      require_relative "../../../lib/monadic/utils/degradation_notifier"
      line = Monadic::Utils::DegradationNotifier.send(:format_line, "Library", "failed: #{FAKE_MISTRAL}", :warning)
      expect(line).not_to include(FAKE_MISTRAL)
    end

    it "DebugHelper.mask_secrets replaces values whole" do
      require_relative "../../../lib/monadic/utils/debug_helper"
      expect(DebugHelper.mask_secrets("k=#{FAKE_TOKEN}")).to eq("k=[redacted]")
    end

    it "ExtraLogger writes lines with secrets replaced" do
      io = StringIO.new
      allow(Monadic::Utils::ExtraLogger).to receive(:enabled?).and_return(true)
      allow(Monadic::Utils::ExtraLogger).to receive(:ensure_file_open)
      Monadic::Utils::ExtraLogger.instance_variable_set(:@file_handle, io)
      Monadic::Utils::ExtraLogger.log { "headers #{FAKE_ANTHROPIC}" }
      Monadic::Utils::ExtraLogger.log_raw("raw #{FAKE_TOKEN}")
      Monadic::Utils::ExtraLogger.log_json("json", { "k" => FAKE_MISTRAL })
      expect(io.string).not_to include(FAKE_ANTHROPIC)
      expect(io.string).not_to include(FAKE_TOKEN)
      expect(io.string).not_to include(FAKE_MISTRAL)
      expect(io.string.scan("[redacted]").size).to eq(3)
    ensure
      Monadic::Utils::ExtraLogger.instance_variable_set(:@file_handle, nil)
    end

    it "a failed transcript segment saves no secret" do
      holder = Object.new.extend(Monadic::Utils::SegmentTranscriber::Shared)
      result = {}
      holder.send(:fail_segment, result, "401 invalid key #{FAKE_MISTRAL}")
      expect(result["error"]).to eq("401 invalid key [redacted]")
    end

    it "the command log saves no secret" do
      require_relative "../../../lib/monadic/app"
      Dir.mktmpdir do |dir|
        log = File.join(dir, "command.log")
        stub_const("MonadicApp::COMMAND_LOG_FILE", log)
        allow(Monadic::Utils::Environment).to receive(:rotate_log)
        allow(Open3).to receive(:capture3)
          .and_return(["out #{FAKE_TOKEN}", "err #{FAKE_MISTRAL}", double(success?: true)])
        app = MonadicApp.new
        allow(app).to receive(:ruby_side_command).and_return({ argv: ["ruby", "x.rb"], chdir: dir, path: "/usr/bin" })
        allow(app).to receive(:ruby_side_env).and_return({})
        app.send(:send_command, command: "x.rb #{FAKE_ANTHROPIC}", container: "ruby")
        written = File.read(log)
        expect(written).not_to include(FAKE_TOKEN)
        expect(written).not_to include(FAKE_MISTRAL)
        expect(written).to include("[redacted]")
      end
    end

    it "an MCP tool result has no secret in either form, even one that JSON escapes" do
      require_relative "../../../lib/monadic/mcp/server"
      stub_const("CONFIG", CONFIG.merge("SERVICE_PASSWORD" => "Abcd\"efgh\\1234\nxyz"))
      allow(Monadic::MCP::Conduit).to receive(:tool?).and_return(true)
      allow(Monadic::MCP::Conduit).to receive(:call).and_return({ "message" => "pw #{CONFIG['SERVICE_PASSWORD']}" })
      server = Monadic::MCP::Server.new!
      res = JSON.parse(server.send(:handle_tool_call, 1, { "name" => "monadic_x", "arguments" => {} }))["result"]
      text_form = JSON.parse(res["content"][0]["text"])
      expect(text_form["message"]).to eq("pw [redacted]")
      expect(res["structuredContent"]["message"]).to eq("pw [redacted]")
    end

    it "send_command gives a block the output without known values and the error redacted" do
      require_relative "../../../lib/monadic/app"
      allow(Monadic::Utils::Environment).to receive(:rotate_log)
      binary = ("\xFF\xD8".b + "data #{FAKE_TOKEN}".b)
      allow(Open3).to receive(:capture3).and_return([binary, "auth Bearer #{'Z' * 24}", double(success?: true)])
      stub_const("MonadicApp::COMMAND_LOG_FILE", File.join(Dir.tmpdir, "spec-command-b-#{Process.pid}.log"))
      app = MonadicApp.new
      allow(app).to receive(:ruby_side_command).and_return({ argv: ["ruby", "x.rb"], chdir: Dir.tmpdir, path: "/usr/bin" })
      allow(app).to receive(:ruby_side_env).and_return({})
      seen = nil
      app.send(:send_command, command: "x.rb", container: "ruby") { |out, err, _st| seen = [out, err] }
      expect(seen[0].b).to start_with("\xFF\xD8".b)
      expect(seen[0].b).not_to include(FAKE_TOKEN.b)
      expect(seen[1]).not_to include("Z" * 24)
    ensure
      FileUtils.rm_f(File.join(Dir.tmpdir, "spec-command-b-#{Process.pid}.log"))
    end

    it "a command result that serialized a secret as JSON carries no secret" do
      require_relative "../../../lib/monadic/app"
      password = "Abcd\"efgh\\1234\nxyz"
      stub_const("CONFIG", CONFIG.merge("SERVICE_PASSWORD" => password))
      allow(Monadic::Utils::Environment).to receive(:rotate_log)
      log = File.join(Dir.tmpdir, "spec-command-j-#{Process.pid}.log")
      stub_const("MonadicApp::COMMAND_LOG_FILE", log)
      allow(Open3).to receive(:capture3).and_return([JSON.generate({ "error" => password }), "", double(success?: true)])
      app = MonadicApp.new
      allow(app).to receive(:ruby_side_command).and_return({ argv: ["ruby", "x.rb"], chdir: Dir.tmpdir, path: "/usr/bin" })
      allow(app).to receive(:ruby_side_env).and_return({})
      out = app.send(:send_command, command: "x.rb", container: "ruby")
      json = out[out.index("{")..]
      expect(JSON.parse(json)["error"]).to eq("[redacted]")
      expect(File.read(log)).not_to include(JSON.generate(password)[1..-2])
    ensure
      FileUtils.rm_f(log)
    end

    it "an import error shown in the browser carries no secret" do
      require_relative "../../../lib/monadic/library/import_tracker"
      id = Monadic::Library::ImportTracker.create
      Monadic::Library::ImportTracker.update(id, stage: "error", error: "extractor: #{FAKE_MISTRAL}")
      expect(Monadic::Library::ImportTracker.get(id)[:error]).not_to include(FAKE_MISTRAL)
    end

    it "the MCP server returns errors and results without secrets" do
      require_relative "../../../lib/monadic/mcp/server"
      server = Monadic::MCP::Server.new!
      err = JSON.parse(server.send(:json_rpc_error, 1, "failed #{FAKE_MISTRAL}", -32_603, "data #{FAKE_TOKEN}"))
      expect(err.to_s).not_to include(FAKE_MISTRAL)
      expect(err.to_s).not_to include(FAKE_TOKEN)
      res = JSON.parse(server.send(:json_rpc_response, 1, { content: [{ type: "text", text: FAKE_ANTHROPIC }] }))
      expect(res.to_s).not_to include(FAKE_ANTHROPIC)
    end
  end
end

# frozen_string_literal: true

require 'spec_helper'

# Cross-cutting invariant: any outbound WebSocket connection opened via
# `Async::HTTP::Endpoint.parse` against a `wss://` URL must explicitly
# pass `alpn_protocols: ["http/1.1"]`.
#
# Why this spec exists (real incident, Phase 0 spike during the Realtime
# STT integration on 2026-05-11):
#   async-http negotiates HTTP/2 via ALPN by default when the server
#   supports it. OpenAI's edge does. The WebSocket Upgrade handshake
#   (RFC 6455) is HTTP/1.1-only — there is no equivalent in HTTP/2 —
#   so without an explicit downgrade the server replies `405 Method Not
#   Allowed` and the WS never opens. The fix is to pin the ALPN protocol
#   list to `["http/1.1"]` at endpoint construction. Captured in
#   tmp/memo/realtime-transcription-plan.md §4 finding #1 and the
#   feedback_websocket_http1_alpn.md memory entry.
#
# Plain `http://` / `https://` parse calls are unaffected (they are not
# WebSocket upgrades), so the check only fires for `wss://` URLs — both
# inline string literals and same-file constants that resolve to a
# `wss://` value.
RSpec.describe "Outbound WebSocket ALPN consistency" do
  ROOT = File.expand_path("../../..", __dir__)

  PRODUCTION_RUBY_FILES = Dir.glob(File.join(ROOT, "lib/**/*.rb")).freeze

  ENDPOINT_PARSE_RE = /Async::HTTP::Endpoint\.parse\s*\(\s*([^,)\s]+)([^)]*)\)/

  # Resolve a `parse()` first-argument expression to a URL string.
  # Handles two forms:
  #   * inline literal: "wss://example/path"
  #   * same-file constant: SOME_URL  (where the same file declares
  #     SOME_URL = "wss://example/path")
  # Returns nil when the URL cannot be statically resolved (treat as
  # "we don't know — don't fail the spec on it").
  def resolve_url_literal(arg_expr, file_content)
    arg_expr = arg_expr.strip
    if arg_expr =~ /\A["']([^"']+)["']\z/
      return Regexp.last_match(1)
    end
    return nil unless arg_expr =~ /\A([A-Z][A-Z0-9_]*)\z/

    const_name = Regexp.last_match(1)
    if file_content =~ /^\s*#{Regexp.escape(const_name)}\s*=\s*["']([^"']+)["']/
      Regexp.last_match(1)
    end
  end

  it "every Async::HTTP::Endpoint.parse on a wss:// URL passes alpn_protocols: [\"http/1.1\"]" do
    offenders = []

    PRODUCTION_RUBY_FILES.each do |path|
      content = File.read(path)

      content.to_enum(:scan, ENDPOINT_PARSE_RE).each do
        match = Regexp.last_match
        first_arg = match[1]
        rest_args = match[2]

        url = resolve_url_literal(first_arg, content)
        next unless url && url.start_with?("wss://")
        next if rest_args =~ /alpn_protocols\s*:\s*\[\s*["']http\/1\.1["']\s*\]/

        line_no = content[0..match.begin(0)].count("\n") + 1
        relative = path.sub("#{ROOT}/", "")
        offenders << "#{relative}:#{line_no}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      The following outbound WebSocket (wss://) connections via
      `Async::HTTP::Endpoint.parse` do not pass `alpn_protocols: ["http/1.1"]`.

      async-http negotiates HTTP/2 by default via ALPN, and the WebSocket
      Upgrade handshake does not exist in HTTP/2 — the server will reply
      with 405 Method Not Allowed and the WS will never open.

      Fix: pass `alpn_protocols: ["http/1.1"]` as a keyword arg to the
      parse call, e.g.

        Async::HTTP::Endpoint.parse(REALTIME_STT_URL, alpn_protocols: ["http/1.1"])

      Offenders:
        #{offenders.join("\n  ")}
    MSG
  end
end

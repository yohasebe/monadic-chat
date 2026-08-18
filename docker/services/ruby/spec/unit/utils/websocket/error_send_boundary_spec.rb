# frozen_string_literal: true

require 'spec_helper'

# Provider error text carries account identifiers — xAI names the team UUID,
# Google the project number, OpenAI the organization — and an error shown in
# the chat is saved with the conversation and travels with any export. Every
# provider names something different, so each new provider re-opens the hole
# unless the scrubbing sits on the delivery boundary rather than at the call
# sites.
#
# There are exactly two ways an error reaches the client: send_error (session
# routed) and send_to_client (pre-session). Both scrub. This spec fails when a
# new call site builds an error payload inline and bypasses them.
RSpec.describe "WebSocket error delivery boundary" do
  ws_dir = File.expand_path("../../../../lib/monadic/utils/websocket", __dir__)
  ws_root = File.expand_path("../../../../lib/monadic/utils/websocket.rb", __dir__)
  files = [ws_root] + Dir[File.join(ws_dir, "**", "*.rb")]

  it "routes every client-bound error through the scrubbing helpers" do
    offenders = files.flat_map do |path|
      name = File.basename(path)
      lines = File.readlines(path)
      lines.each_with_index.filter_map do |line, i|
        next unless line.include?('"type" => "error"')
        next if line.strip.start_with?("#")
        # send_to_client scrubs whatever it is handed, so its call sites are
        # safe — including the multi-line form where the hash opens above.
        next if lines[[i - 3, 0].max..i].any? { |l| l.include?("send_to_client(") }
        # The payload send_error itself builds, after scrubbing.
        next if name == "websocket.rb" && line.include?("scrubbed")
        # Upstream provider events normalized into a common dialect; consumed
        # in-process, never delivered to a client as-is.
        next if name == "sts_stream_handler.rb" && line.include?("events <<")

        "#{name}:#{i + 1}: #{line.strip}"
      end
    end

    expect(offenders).to be_empty, <<~MSG
      An error payload is built inline instead of going through send_error /
      send_to_client, so provider identifiers would reach the chat unscrubbed:

        #{offenders.join("\n  ")}

      Use send_error(content, ws_session_id) — it scrubs, formats and delivers.
    MSG
  end

  it "keeps the scrubber covering every identifier shape we have seen" do
    require_relative "../../../../lib/monadic/utils/error_formatter"
    scrub = ->(t) { Monadic::Utils::ErrorFormatter.scrub_identifiers(t) }

    # One sample per provider convention observed in the wild.
    {
      "your team 00000000-1111-2222-3333-444444444444 lacks access" => "00000000-1111-2222-3333-444444444444",
      "quota exceeded for org-AbCdEf123456789" => "org-AbCdEf123456789",
      "project proj_9f8e7d6c5b4a3210 is disabled" => "proj_9f8e7d6c5b4a3210",
      "see request req_0123456789abcdef" => "req_0123456789abcdef",
      "API not enabled in project 123456789012" => "123456789012"
    }.each do |message, identifier|
      expect(scrub.call(message)).not_to include(identifier), "leaked #{identifier}"
    end

    # Ordinary text must survive untouched, or errors stop being actionable.
    plain = "Rate limit exceeded. Please retry in 20 seconds."
    expect(scrub.call(plain)).to eq(plain)
  end
end

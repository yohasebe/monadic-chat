# frozen_string_literal: true

require 'spec_helper'

# Test the orchestration history pruning algorithm used by vendor helpers.
# The logic is identical across OpenAI, Gemini, and Grok — we extract and
# verify it here to avoid coupling to any single vendor's api_request method.
RSpec.describe "Orchestration history pruning" do
  def prune(context, keep_rounds:)
    first_msg = context.first
    user_indices = context.each_index.select { |i| context[i]&.[]("role") == "user" }

    needed = keep_rounds + 1
    if user_indices.length >= needed
      keep_from = user_indices[-needed]
      context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
    elsif user_indices.length >= 2
      keep_from = user_indices.first
      context = keep_from.zero? ? context : [first_msg] + context[keep_from..]
    else
      last_user_msg = context.reverse.find { |msg| msg&.[]("role") == "user" }
      context = [first_msg]
      context << last_user_msg if last_user_msg && first_msg != last_user_msg
    end
    context.compact
  end

  let(:sys) { { "role" => "system", "text" => "You are a helper" } }

  def user(n)  = { "role" => "user",      "text" => "user-#{n}" }
  def asst(n)  = { "role" => "assistant",  "text" => "asst-#{n}" }
  def tool(n)  = { "role" => "tool",       "text" => "tool-#{n}" }

  context "with keep_rounds=3 (default for Image/VideoGenerator)" do
    it "keeps last 3 rounds + current when enough history exists" do
      # 5 rounds: system + 5*(user+tool+asst) + current user
      context = [sys]
      5.times { |i| context.push(user(i), tool(i), asst(i)) }
      context.push(user(5)) # current

      result = prune(context, keep_rounds: 3)

      # Should keep: system + rounds 3,4,5(current) = system + user3..user5
      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      expect(user_texts).to eq(%w[user-2 user-3 user-4 user-5])
    end

    it "keeps all messages when fewer than keep_rounds+1 user messages" do
      context = [sys, user(0), tool(0), asst(0), user(1), tool(1), asst(1), user(2)]

      result = prune(context, keep_rounds: 3)

      # 3 user messages < needed(4), but >= 2 → keep from first user
      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      expect(user_texts).to eq(%w[user-0 user-1 user-2])
    end

    it "handles single user message" do
      context = [sys, user(0)]

      result = prune(context, keep_rounds: 3)

      expect(result).to eq([sys, user(0)])
    end

    it "handles no user messages" do
      context = [sys]

      result = prune(context, keep_rounds: 3)

      expect(result).to eq([sys])
    end
  end

  context "with keep_rounds=1 (legacy behavior)" do
    it "keeps only last 1 round + current" do
      context = [sys, user(0), asst(0), user(1), asst(1), user(2)]

      result = prune(context, keep_rounds: 1)

      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      expect(user_texts).to eq(%w[user-1 user-2])
    end
  end

  context "with keep_rounds=5" do
    it "keeps up to 5 previous rounds" do
      context = [sys]
      7.times { |i| context.push(user(i), asst(i)) }
      context.push(user(7))

      result = prune(context, keep_rounds: 5)

      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      # needed=6, 8 user msgs total → keep from [-6]=user-2
      expect(user_texts).to eq(%w[user-2 user-3 user-4 user-5 user-6 user-7])
    end
  end

  context "when first_msg is a user message (e.g., Gemini auto-greeting)" do
    it "does not duplicate first_msg when keep_from is zero" do
      # Gemini can auto-add "Hi, there!" as first message
      context = [user(0), asst(0), user(1), asst(1), user(2)]

      result = prune(context, keep_rounds: 3)

      # needed=4, 3 user msgs < 4, but >= 2 → keep_from=user_indices.first=0
      # Should NOT duplicate user(0)
      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      expect(user_texts).to eq(%w[user-0 user-1 user-2])
      expect(result.first).to eq(user(0))
      expect(result.count { |m| m["text"] == "user-0" }).to eq(1)
    end

    it "does not duplicate when many rounds with user-first context" do
      context = [user(0)]
      5.times { |i| context.push(asst(i), user(i + 1)) }

      result = prune(context, keep_rounds: 3)

      # 6 user messages, needed=4 → keep_from=user_indices[-4]=user(2)
      # first_msg=user(0), keep_from != 0, so prepend is safe
      user_texts = result.select { |m| m["role"] == "user" }.map { |m| m["text"] }
      expect(user_texts).to eq(%w[user-0 user-2 user-3 user-4 user-5])
    end
  end

  context "preserves interleaved tool/assistant messages" do
    it "keeps tool results between retained user messages" do
      context = [sys, user(0), tool(0), asst(0), user(1), tool(1), asst(1), user(2)]

      result = prune(context, keep_rounds: 1)

      # Should keep: sys + user1, tool1, asst1, user2
      expect(result.map { |m| m["text"] }).to eq([
        "You are a helper", "user-1", "tool-1", "asst-1", "user-2"
      ])
    end
  end
end

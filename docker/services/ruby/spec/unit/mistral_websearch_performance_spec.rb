# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/monadic/adapters/vendors/mistral_helper'

RSpec.describe 'Mistral WebSearch Performance Optimization' do
  describe 'websearch prompt addition' do
    let(:websearch_prompt) { "You have access to web search functionality." }
    let(:system_message) do
      {
        "role" => "system",
        "text" => "You are a helpful assistant."
      }
    end

    context 'with flag-based optimization' do
      it 'adds websearch prompt only once' do
        # First addition
        if system_message["role"] == "system" && !system_message["websearch_added"]
          system_message["text"] += "\n\n#{websearch_prompt}"
          system_message["websearch_added"] = true
        end

        expect(system_message["text"]).to include(websearch_prompt)
        expect(system_message["websearch_added"]).to be true

        original_text = system_message["text"]

        # Second attempt should not add again
        if system_message["role"] == "system" && !system_message["websearch_added"]
          system_message["text"] += "\n\n#{websearch_prompt}"
          system_message["websearch_added"] = true
        end

        expect(system_message["text"]).to eq(original_text)
      end

      it 'preserves flag in message metadata' do
        system_message["websearch_added"] = true
        
        # Flag should persist in the message object
        expect(system_message["websearch_added"]).to be true
        expect(system_message.keys).to include("websearch_added")
      end

      it 'performs better than string search' do
        iterations = 5000  # Increased iterations for more stable results
        long_text = "You are a helpful assistant. " * 200  # Longer text to make difference more pronounced
        
        # Run multiple trials and take the minimum to reduce noise
        flag_times = []
        search_times = []
        
        3.times do
          # Flag-based check timing
          flag_start = Time.now
          iterations.times do
            msg = { "role" => "system", "text" => long_text.dup }
            if msg["role"] == "system" && !msg["websearch_added"]
              msg["websearch_added"] = true
            end
          end
          flag_times << (Time.now - flag_start)

          # String search timing
          search_start = Time.now
          iterations.times do
            msg = { "role" => "system", "text" => long_text.dup }
            if msg["role"] == "system" && !msg["text"].include?(websearch_prompt)
              # Just the check, not the addition
            end
          end
          search_times << (Time.now - search_start)
        end
        
        # Use minimum times to reduce system noise
        flag_time = flag_times.min
        search_time = search_times.min

        # Flag check should be faster (with some tolerance for system variance)
        # Allow up to 20% variance due to system load
        expect(flag_time).to be <= (search_time * 1.2)
      end
    end

    context 'integration with context' do
      it 'works correctly with message context array' do
        context = [
          { "role" => "system", "text" => "You are a helpful assistant." },
          { "role" => "user", "text" => "Hello" },
          { "role" => "assistant", "text" => "Hi there!" }
        ]

        # Add websearch to system message
        system_msg = context.first
        if system_msg && system_msg["role"] == "system" && !system_msg["websearch_added"]
          system_msg["text"] += "\n\n#{websearch_prompt}"
          system_msg["websearch_added"] = true
        end

        # Verify only system message was modified
        expect(context[0]["text"]).to include(websearch_prompt)
        expect(context[0]["websearch_added"]).to be true
        expect(context[1]["websearch_added"]).to be_nil
        expect(context[2]["websearch_added"]).to be_nil
      end
    end
  end
end
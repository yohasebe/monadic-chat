# frozen_string_literal: true

require "json"
require "digest"

module Monadic
  module Utils
    # A record of what the model asked for and what each round cost, for
    # comparing prompts by measurement. Written only while
    # MONADIC_TRIAL_LOG names a folder in the shell's environment (never
    # from the config file), one JSON line per event in events.jsonl.
    #
    # It holds no message text and no tool arguments: a tool call is kept as
    # its name, its call id and a digest of its arguments, so two calls with
    # the same arguments can be told apart from two different ones. The
    # digest does not make the record anonymous: short arguments can be
    # guessed back from it. The file is the owner's only (0600). Nothing
    # is written when the folder does not exist or is in the shared folder.
    module TrialLog
      FLAG = "MONADIC_TRIAL_LOG"
      FILE_NAME = "events.jsonl"
      MUTEX = Mutex.new

      module_function

      def dir(env = ENV)
        value = env[FLAG].to_s.strip
        value.empty? ? nil : value
      end

      # The tool calls of one model reply, as the model sent them (before
      # duplicates are dropped).
      def tool_calls(calls, app:, depth:, env: ENV)
        Array(calls).each do |call|
          function = call["function"] || {}
          write({ "event" => "tool_requested", "app" => app.to_s, "depth" => depth.to_i,
                  "tool" => function["name"].to_s, "call_id" => call["id"].to_s,
                  "arguments_digest" => digest(function["arguments"]) }, env: env)
        end
      end

      # The token counts of one model reply.
      def usage(usage, app:, env: ENV)
        return unless usage.is_a?(Hash)

        details = usage["input_tokens_details"] || usage["prompt_tokens_details"] || {}
        write({ "event" => "usage", "app" => app.to_s,
                "input_tokens" => usage["input_tokens"] || usage["prompt_tokens"],
                "cached_tokens" => details["cached_tokens"],
                "output_tokens" => usage["output_tokens"] || usage["completion_tokens"] }, env: env)
      end

      def write(record, env: ENV)
        folder = dir(env)
        return unless folder

        context = defined?(Monadic::Workspace::RequestContext) ? Monadic::Workspace::RequestContext.current : nil
        line = JSON.generate(record.merge("request_id" => context&.request_id, "at" => Time.now.utc.iso8601(3)))
        return unless File.directory?(folder) && defined?(Monadic::History::Store)

        Monadic::History::Store.refuse_inside_shared_folder!(folder)
        MUTEX.synchronize do
          File.open(File.join(folder, FILE_NAME), File::WRONLY | File::APPEND | File::CREAT, 0o600) { |f| f.puts(line) }
        end
      rescue StandardError
        nil # measuring must never break a reply
      end

      def digest(arguments)
        Digest::SHA256.hexdigest(arguments.to_s)[0, 16]
      end
      private_class_method :digest
    end
  end
end

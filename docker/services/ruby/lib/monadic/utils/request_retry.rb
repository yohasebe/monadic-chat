# frozen_string_literal: true

module Monadic
  module Utils
    # What the vendor helpers' request retry needs: a copy of the request
    # body for each attempt (a call adds fields of its own to the body it is
    # given), and a block that passes everything on to the browser while it
    # records whether part of the reply has gone out. Once it has, a failed
    # request is not sent again, so a reply is not shown twice.
    module RequestRetry
      # Sent before or around a reply, not part of it.
      NOTICE_TYPES = %w[wait system_info info processing_status].freeze

      module_function

      def copy(body)
        Marshal.load(Marshal.dump(body))
      rescue TypeError
        body
      end

      # nil when there is no block; state[:replied] becomes true at the first
      # message that is not a notice.
      def relay(block, state)
        return nil unless block

        proc do |*args|
          first = args.first
          state[:replied] = true unless first.is_a?(Hash) && NOTICE_TYPES.include?(first["type"])
          block.call(*args)
        end
      end
    end
  end
end

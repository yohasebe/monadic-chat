# frozen_string_literal: true

require 'json'
require 'timeout'
require_relative 'capture'
require_relative '../utils/capability_request'

module Monadic
  module Workbench
    # Takes a page's answer to a capture (Capture) at
    # POST /workbench/capture/<id>, ahead of the application so that the
    # request is not written to the access log: the id in the address is
    # the permission to answer (it was written only to the connection the
    # capture was asked of), not the cookie. Anything that is not a JSON
    # POST sent by a page of this server (Sec-Fetch-Site: same-origin), of
    # at most Capture::BODY_LIMIT bytes, to an id waiting for its answer,
    # gets the same "not found"; the body is read only after the id is
    # known to wait, and only until the capture's deadline. 204 says the
    # answer was handed over, not that the look kept it.
    class CaptureServer
      PREFIX = '/workbench/capture/'

      def initialize(app)
        @app = app
      end

      def call(env)
        path = env['PATH_INFO'].to_s
        return @app.call(env) unless path.start_with?(PREFIX)

        take(env, path.delete_prefix(PREFIX))
      rescue StandardError
        not_found
      end

      private

      def take(env, id)
        return not_found unless Monadic::Utils::CapabilityRequest.same_origin_post?(env)
        return not_found unless id.match?(Capture::ID) && json?(env['CONTENT_TYPE'])

        length = env['CONTENT_LENGTH'].to_s
        return not_found unless length.match?(/\A\d{1,8}\z/) && length.to_i <= Capture::IMAGE_LIMIT + Capture::BODY_LIMIT

        taken = Capture.reading(id, length.to_i) do |deadline|
          body = read(env['rack.input'], length.to_i, deadline)
          body && parse(body)
        end
        taken ? Monadic::Utils::CapabilityRequest.taken : not_found
      end

      def json?(type)
        type.to_s.split(';').first.to_s.strip.casecmp?('application/json')
      end

      # Exactly length bytes, read before deadline, or nil.
      def read(input, length, deadline)
        left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        return nil unless input && left.positive?

        body = Timeout.timeout(left) { input.read(length + 1) }.to_s
        body.bytesize == length ? body : nil
      rescue Timeout::Error
        nil
      end

      def parse(body)
        value = JSON.parse(body)
        value.is_a?(Hash) ? value : nil
      rescue JSON::ParserError
        nil
      end

      def not_found
        Monadic::Utils::CapabilityRequest.not_found
      end
    end
  end
end

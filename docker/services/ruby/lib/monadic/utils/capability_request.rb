# frozen_string_literal: true

module Monadic
  module Utils
    # What the server's capability addresses share (a page's answer to a
    # capture, a page stopping its answer): the secret in the address is the
    # permission, not the cookie, so these are handled ahead of the
    # application (never written to the access log), only for a POST sent by
    # a page of this server (Sec-Fetch-Site: same-origin), and anything else
    # gets the same "not found".
    module CapabilityRequest
      HEADERS = {
        'cache-control' => 'no-store',
        'x-content-type-options' => 'nosniff',
        'cross-origin-resource-policy' => 'same-origin',
        'referrer-policy' => 'no-referrer',
        'content-security-policy' => "default-src 'none'"
      }.freeze

      module_function

      def same_origin_post?(env)
        env['REQUEST_METHOD'] == 'POST' && env['HTTP_SEC_FETCH_SITE'] == 'same-origin'
      end

      # 204: what was sent was taken (not what came of it).
      def taken
        [204, HEADERS.dup, []]
      end

      def not_found
        text = 'Not found'
        [404, HEADERS.merge('content-type' => 'text/plain', 'content-length' => text.bytesize.to_s), [text]]
      end
    end
  end
end

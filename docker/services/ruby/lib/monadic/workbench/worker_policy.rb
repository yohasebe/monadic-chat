# frozen_string_literal: true

module Monadic
  module Workbench
    # The scripts the work screen runs in a worker (the Vega-Lite charts),
    # served with a policy of their own: the worker may load nothing and
    # run no text as code. A worker takes the policy of its script's
    # response, not the page's.
    class WorkerPolicy
      PATHS = ['/vendor/vega/vega-worker.mjs'].freeze
      POLICY = "default-src 'none'"

      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)
        return [status, headers, body] unless PATHS.include?(env['PATH_INFO'])

        headers = headers.dup
        headers.delete_if { |key, _| key.to_s.casecmp?('content-security-policy') }
        headers['content-security-policy'] = POLICY
        [status, headers, body]
      end
    end
  end
end

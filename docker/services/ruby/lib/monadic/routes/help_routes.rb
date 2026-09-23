# frozen_string_literal: true

require_relative '../help'

module Monadic
  module Routes
    module HelpRoutes
      def self.registered(app)
        # These routes inherit the application's AuthMiddleware and Rack
        # protection, just like the other data-management routes.
        app.get '/help/database' do
          @ui_language = ENV['UI_LANGUAGE'] || 'en'
          headers 'Cache-Control' => 'no-store'
          erb :help_database
        end

        app.get '/help/database/status' do
          content_type :json
          headers 'Cache-Control' => 'no-store'
          Monadic::Help.installation.status.to_json
        rescue StandardError
          status 503
          { state: 'unavailable', searchable: false, reason: 'Help data service is unavailable.' }.to_json
        end

        app.post '/help/database/install' do
          content_type :json
          headers 'Cache-Control' => 'no-store'
          origin = request.env['HTTP_ORIGIN']
          if origin && origin != request.base_url
            halt 403, { error: 'Installation requires a same-origin request.' }.to_json
          end
          # There are no client-selectable sources or target collections.
          body = request.body&.read(1025).to_s
          valid_body = body.empty? || (request.media_type == 'application/json' && body.bytesize <= 1024 && JSON.parse(body) == {})
          unless params.empty? && valid_body
            halt 400, { error: 'Installation does not accept parameters.' }.to_json
          end

          result = Monadic::Help.installation.start
          status(result[:accepted] ? 202 : 409)
          result.to_json
        rescue JSON::ParserError
          halt 400, { error: 'Installation does not accept parameters.' }.to_json
        rescue StandardError
          status 503
          { accepted: false, state: 'unavailable', retryable: true,
            error: 'Help data service is unavailable.' }.to_json
        end
      end
    end
  end
end

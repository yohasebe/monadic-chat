# frozen_string_literal: true

require 'uri'
require_relative '../../work_screen'
require_relative '../../work_screen/snapshot'

module Monadic
  module Workbench
    module Look
      # What a look gives of the chat's browser on the work screen: a
      # picture of the viewport of the window the tools act on, taken now
      # (WorkScreen::Snapshot), with the page's title and its address (only
      # http(s), without user information, query or fragment). Both are what
      # the browser said near the moment of the picture, not proof that they
      # belong to it.
      module Browser
        TITLE_CHARS = 200
        URL_CHARS = 500

        module_function

        # The picture of the browser that item (selected by caller's tab)
        # is, before deadline: the parts of an observation, with the
        # binding checked again by holds (a lambda) before it is kept.
        def look(item, caller, deadline, snapshot: WorkScreen::Snapshot)
          unless WorkScreen.available?
            raise Refused.new('browser_unavailable', 'the browser cannot be looked at here')
          end

          view = MonadicSharedTools::BrowserOwner.view(caller.chat_id)
          unless view && view.instance == item.dig('browser', 'instance') && view.epoch == caller.epoch
            raise Refused.new('changed', 'the browser on the work screen is closed or another one now')
          end
          raise Refused.new('drawing', 'the browser has no window to look at yet') unless view.window

          binding = WorkScreen::BrowserBinding.new(caller.tab, caller.generation, caller.chat_id, view.epoch,
                                                   view.instance, view.session, view.window)
          shot = snapshot.take(binding, deadline: deadline)
          image = ImageValue.checked(shot[:png], source: 'workbench_browser')
          { name: title(shot[:title]), path: address(shot[:url]), image: image, crop: shot[:crop],
            holds: -> { binding.broken.nil? } }
        rescue WorkScreen::Snapshot::Failed => e
          raise Refused.new(REASONS.include?(e.reason) ? e.reason : 'browser_unavailable', e.message)
        end

        # The page's title, as text of one line, at most TITLE_CHARS.
        def title(text)
          clean = text.to_s.encode('UTF-8', invalid: :replace, undef: :replace).gsub(/[[:cntrl:]]+/, ' ').strip
          clean.empty? ? 'browser' : clean[0, TITLE_CHARS]
        end

        # scheme://host[:port]/path of an http(s) address, or '' for any
        # other.
        def address(url)
          uri = URI.parse(url.to_s)
          return '' unless %w[http https].include?(uri.scheme) && uri.host

          port = uri.port == uri.default_port ? '' : ":#{uri.port}"
          "#{uri.scheme}://#{uri.host}#{port}#{uri.path}"[0, URL_CHARS]
        rescue URI::InvalidURIError
          ''
        end
      end
    end
  end
end

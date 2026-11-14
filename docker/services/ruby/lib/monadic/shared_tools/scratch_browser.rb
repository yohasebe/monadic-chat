# frozen_string_literal: true

require_relative 'browser_owner'

module MonadicSharedTools
  # A browser session of its own for one job (a diagram preview): started,
  # used and closed within one call, apart from the chat's browser
  # (BrowserOwner), so the two never replace or close each other's page.
  module ScratchBrowser
    module_function

    # Starts a session on url, in a browser slot of its own (BrowserOwner),
    # and yields (run, start_output): run.call(args) runs a web_navigator
    # action (args, an Array) on that session and returns its output; run
    # is nil when the session did not start. The session is closed when the
    # block returns, however it returns, and the screenshots its actions
    # left in the shared folder are removed: the job keeps what it needs
    # under a name of its own. Raises BrowserOwner::Refused (Private, no
    # free slot, no Selenium).
    def with_session(url)
      BrowserOwner.with_job do |name_session|
        session_id = nil
        shots = []
        begin
          start_output = BrowserOwner.navigator(['--action', 'start', '--managed', '--url', url.to_s])
          shots.concat(screenshots_of(start_output))
          session_id = BrowserOwner.result_of(start_output)&.dig('session_id')
          name_session.call(session_id) if session_id
          run = session_id && lambda do |args|
            BrowserOwner.navigator([*args, '--managed', '--session-id', session_id]).tap do |output|
              shots.concat(screenshots_of(output))
            end
          end
          yield(run, start_output)
        ensure
          BrowserOwner.close_quietly(session_id) if session_id
          remove_screenshots(shots)
        end
      end
    end

    # The names web_navigator.py gave the screenshots an action took.
    SCREENSHOT_NAME = /\Abrowser_\d+\.png\z/

    def screenshots_of(output)
      result = BrowserOwner.result_of(output) || {}
      [result['screenshot'], *Array(result['screenshots'])].grep(SCREENSHOT_NAME)
    end

    def remove_screenshots(names)
      folder = Monadic::Utils::Environment.shared_volume
      names.uniq.each do |name|
        Monadic::Utils::SharedPathGuard.delete_file!(File.join(folder, name))
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        nil
      end
    end
  end
end

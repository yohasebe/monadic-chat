# frozen_string_literal: true

require 'json'
require_relative '../workbench/board'
require_relative '../workbench/caller'
require_relative '../workbench/channel'
require_relative '../workbench/look'
require_relative '../workbench/put'
require_relative '../workbench/shown'
require_relative '../history/policy'

module MonadicSharedTools
  # What every app can do with the work screen (the workbench beside the
  # chat): show a file of the shared folder there. No provider's API is
  # called. The file is not copied: the work screen shows it as it is when
  # shown, and says so when it changes or is gone.
  module WorkbenchTools
    # The prefixes a model may put before a path of the shared folder.
    SHARED_PREFIXES = %r{\A/(?:monadic/)?data/}

    # workbench: who called (Monadic::Workbench::Caller), given by the
    # server, never by the model.
    def show_on_workbench(path:, workbench: nil)
      return refused('this reply cannot show anything in the work screen') unless workbench

      private_chat = Monadic::History::Policy.private?(workbench.session) ||
                     Monadic::History::Policy.known_private?(workbench.chat_id)
      board = Monadic::Workbench::Board.for(workbench.chat_id, private: private_chat)
      item, = board.add_file(path: path.to_s.sub(SHARED_PREFIXES, ''), origin: workbench.origin, epoch: workbench.epoch)
      Monadic::Workbench::Shown.add(workbench.request_id, item)
      Monadic::Workbench::Channel.changed(workbench.chat_id)
      JSON.generate({ 'status' => 'shown_in_work_screen', 'path' => item.dig('file', 'path'),
                      'note' => 'The file is shown in the work screen as it is now. It was not copied.' })
    rescue Monadic::Workbench::Board::Refused => e
      refused(e.message)
    rescue Monadic::Workbench::FileItem::Busy
      refused('the work screen is reading other files now; try again in a moment')
    end

    # A text the model made, written as a new file of the chat's folder
    # and shown in the work screen (Monadic::Workbench::Put). A file that
    # was written but could not be shown is said so, with its path.
    def put_on_workbench(name:, content:, workbench: nil)
      result = Monadic::Workbench::Put.run(workbench, name: name, content: content)
      Monadic::Workbench::Channel.changed(workbench.chat_id) if result[:shown]
      out = { 'status' => result[:shown] ? 'shown_in_work_screen' : 'written_not_shown', 'path' => result[:path] }
      out['reason'] = result[:reason] unless result[:shown]
      JSON.generate(out)
    rescue Monadic::Workbench::Put::Refused => e
      "❌ Nothing was put on the work screen: #{e.message}."
    end

    # What the asking tab has selected in the work screen, read now
    # (Monadic::Workbench::Look): a Look::Result whose image, if any, the
    # provider's helper places after the result, or a refusal.
    def look_at_workbench(scope: 'visible', workbench: nil)
      Monadic::Workbench::Look.run(workbench, scope: scope)
    end

    private

    def refused(reason)
      "❌ The file was not shown in the work screen: #{reason}."
    end
  end
end

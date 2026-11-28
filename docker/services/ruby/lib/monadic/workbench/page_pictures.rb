# frozen_string_literal: true

require_relative '../shared_tools/browser_owner'
require_relative '../workspace/chats'
require_relative '../workspace/folders'
require_relative '../utils/shared_path_guard'

module Monadic
  module Workbench
    # The pictures of a chat's open browser taken when a turn ends: the
    # browser stays in Now for the next turn, and the page as the turn left
    # it goes down with that turn as an image (Board#shift! makes the
    # pending item). The picture is taken on a thread of its own, against
    # the browser the turn ended with (Binding, not a tab's), and kept in the
    # chat's folder (pages/); the item becomes that image, or, when no
    # picture can be taken, a link to the page.
    #
    # While a chat's pictures are being taken, the tools wait before acting
    # on its browser (wait), so the next turn's actions are not pictured.
    module PagePictures
      DIRNAME = 'pages'
      # Seconds a picture may take.
      SECONDS = 10
      # The most names tried for a picture's file.
      NAMES = 1000

      # The browser a turn ended with: the chat's epoch, the browser's
      # instance and Selenium session, and the window the tools act on.
      Binding = Struct.new(:chat, :epoch, :instance, :session, :window) do
        # Why it no longer holds (:replaced, :browser_closed, :window), or nil.
        def broken(view = MonadicSharedTools::BrowserOwner.view(chat))
          return :replaced unless Monadic::Workspace::Chats.epoch(chat) == epoch
          return :browser_closed unless view && view.epoch == epoch && view.instance == instance && view.session == session
          return :window unless view.window == window

          nil
        end
      end

      @lock = Mutex.new
      @done = ConditionVariable.new
      @held = Hash.new(0)
      # How the pictures are taken: on a thread of their own (tests run them
      # in place).
      @spawn = ->(&work) { Thread.new(&work).report_on_exception = false }

      class << self
        attr_accessor :spawn

        # The browser of chat as the turn ends, or nil when it has no window
        # to picture, or the browser cannot be reached from here
        # (WorkScreen.available?).
        def binding_for(chat)
          return nil unless defined?(Monadic::WorkScreen) && Monadic::WorkScreen.respond_to?(:available?) &&
                            Monadic::WorkScreen.available?

          view = MonadicSharedTools::BrowserOwner.view(chat)
          view&.window ? Binding.new(chat, view.epoch, view.instance, view.session, view.window) : nil
        end

        # Pictures for chat are about to be taken (under the board's lock,
        # before it is let go).
        def hold(chat)
          @lock.synchronize { @held[chat] += 1 }
        end

        # Waits, at most limit seconds, until chat's pictures are taken.
        def wait(chat, limit: SECONDS + 2)
          @lock.synchronize do
            by = clock + limit
            while @held[chat].positive?
              left = by - clock
              break unless left.positive?

              @done.wait(@lock, left)
            end
          end
        end

        def taking?(chat)
          @lock.synchronize { @held[chat].positive? }
        end

        # A tool on chat's browser reported the page it shows (result's
        # page_info): its item keeps the address and title, in the form a
        # look gives them.
        def note(chat, result)
          info = result.is_a?(Hash) && result[:page_info]
          return unless info.is_a?(Hash) && Monadic::Workspace::Ids.valid?(:chat, chat)

          view = MonadicSharedTools::BrowserOwner.view(chat) or return
          url = Look::Browser.address(info[:url] || info['url'])
          title = info[:title] || info['title']
          Board.existing(chat)&.note_page(view.instance, url: url.empty? ? nil : url,
                                                         title: title.to_s.strip.empty? ? nil : Look::Browser.title(title))
        rescue StandardError => e
          log(e)
        end

        # The chat's browser is about to be closed by a tool (holding its
        # actions): its item keeps the last page, pictured now when it can
        # be, else as a link.
        def before_close(chat)
          return unless Monadic::Workspace::Ids.valid?(:chat, chat)

          view = MonadicSharedTools::BrowserOwner.view(chat) or return
          board = Board.existing(chat) or return
          binding = binding_for(chat)
          item_id = board.close_browser!(view.instance, binding: binding)
          return unless item_id && binding

          begin
            take(chat, item_id, binding)
          ensure
            release(chat)
          end
          Channel.changed(chat) if defined?(Channel) && Channel.respond_to?(:changed)
        rescue Board::Refused => e
          log(e)
        end

        # Takes the pictures of pending ([{ item_id:, binding: }], held
        # with hold) and puts each on the board's item.
        def take_later(chat, pending)
          return if pending.empty?

          spawn.call do
            pending.each { |entry| take(chat, entry[:item_id], entry[:binding]) }
          ensure
            release(chat)
            Channel.changed(chat) if defined?(Channel) && Channel.respond_to?(:changed)
          end
        end

        def take(chat, item_id, binding)
          board = Board.existing(chat) or return
          shot = binding && snapshot(binding)
          unless shot
            board.page_unpictured(item_id)
            return
          end

          path = keep(chat, shot[:png])
          if path
            board.page_pictured(item_id, path: path, url: shot[:url], title: shot[:title])
          else
            board.page_unpictured(item_id, url: shot[:url], title: shot[:title])
          end
        rescue Board::Refused, SystemCallError, Monadic::Utils::SharedPathGuard::InvalidPath => e
          log(e)
          board&.page_unpictured(item_id)
        end

        # { png:, url:, title: } of the page now, its address and title as a
        # look gives them; nil when no picture could be taken.
        def snapshot(binding)
          shot = Monadic::WorkScreen::Snapshot.take(binding, deadline: clock + SECONDS)
          { png: shot[:png], url: Look::Browser.address(shot[:url]), title: Look::Browser.title(shot[:title]) }
        rescue StandardError => e
          log(e)
          nil
        end

        # The chat's folder path (relative to the shared folder) of the
        # picture written there, or nil.
        def keep(chat, png)
          folder = Monadic::Workspace::Folders.ensure_for_chat!(chat, app_name: 'Chat')
          return nil unless folder[:status] == :ready

          relative = File.join(folder[:relative_dir], DIRNAME)
          dir = File.join(File.realpath(Monadic::Utils::Environment.data_path), relative)
          Monadic::Utils::SharedPathGuard.mkdir_p!(dir, strict: true)
          start = Dir.children(dir).size + 1
          (start...(start + NAMES)).each do |n|
            name = "page-#{n}.png"
            Monadic::Utils::SharedPathGuard.write_file!(File.join(dir, name), png, mode: 'wb', replace: false, strict: true)
            return File.join(relative, name)
          rescue Errno::EEXIST
            next
          end
          nil
        end

        def release(chat)
          @lock.synchronize do
            @held[chat] -= 1
            @held.delete(chat) unless @held[chat].positive?
            @done.broadcast
          end
        end

        # For tests.
        def reset!
          @lock.synchronize do
            @held.clear
            @done.broadcast
          end
        end

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end

        def log(error)
          return unless defined?(Monadic::Utils::ExtraLogger)

          Monadic::Utils::ExtraLogger.log { "[Workbench] page not pictured: #{error.class}" }
        end
      end
    end
  end
end

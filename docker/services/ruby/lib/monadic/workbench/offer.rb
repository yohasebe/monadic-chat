# frozen_string_literal: true

require_relative 'board'
require_relative 'caller'
require_relative 'job_output'
require_relative 'record'

module Monadic
  module Workbench
    # Places what a generator made for a reply in the chat's folder, puts it
    # on the chat's workbench and tells the reply to end (Offered): the image
    # is there for the user to look at, edit further, save elsewhere or take
    # off the board. The image belongs to the reply's request: when the reply's message is recorded,
    # it is that message's (Channel.reply_recorded). When the reply ends
    # without a message (Cancel, an error, a closed connection), the request
    # is closed: an image it already put on the board stays, and nothing
    # that arrives from it later is taken.
    module Offer
      CLOSED_LIMIT = 500
      # The keys of a reply's final message that name what it put on the
      # board, and the record of what it made (Record).
      ITEMS_KEY = 'workbench_items'
      ARTIFACTS_KEY = 'workbench_artifacts'

      @closed = {}
      @in_flight = {}
      @lock = Mutex.new

      module_function

      # The reply's own words when it ends with an image on the workbench.
      def reply_text(offered)
        text = "The image is in the work screen and in the shared folder: `#{offered.path}`"
        offered.notice ? "#{offered.notice}\n\n#{text}" : text
      end

      # Ends a reply whose tool put an image on the workbench, for every
      # provider: one short line, then the reply is done (each event goes to
      # emit once). The result names the item, so the message recorded from
      # it (not one of text written before) is the image's.
      def end_reply(offered, &emit)
        text = reply_text(offered)
        emit&.call({ 'type' => 'fragment', 'content' => text, 'is_first' => true })
        emit&.call({ 'type' => 'message', 'content' => 'DONE', 'finish_reason' => 'stop' })
        [{ 'choices' => [{ 'finish_reason' => 'stop',
                           'message' => { 'content' => text, ITEMS_KEY => [offered.item_id],
                                          ARTIFACTS_KEY => [offered.entry] } }] }]
      end

      # Whether a provider's results are a reply end_reply made.
      def ended_reply?(results)
        message = results.is_a?(Array) && results.dig(0, 'choices', 0, 'message')
        message.is_a?(Hash) && message.key?(ITEMS_KEY)
      end

      # The first file the run left in its output folder as the image (a run
      # for a chat makes one image; others are left out). derived_from: the
      # image it was made from ({artifact_id:, sha256:}).
      def image(caller, job_dir, derived_from: nil)
        name = JobOutput.files(job_dir).first or raise Board::Refused, 'the generator made no image'
        bytes = JobOutput.read(job_dir, name)
        board = Board.for(caller.chat_id)
        params = caller.session && (caller.session[:parameters] || caller.session['parameters']) || {}
        @lock.synchronize { @in_flight[caller.request_id] = caller.chat_id }
        item = board.add_image(bytes: bytes, epoch: caller.epoch, name: name, run: File.basename(job_dir),
                               app_name: params['app_name'], derived_from: derived_from,
                               origin: caller.origin,
                               unless_closed: -> { closed?(caller.request_id) })
        entry = item['artifact'].slice(*Record::FIELDS)
        Offered.new(chat_id: caller.chat_id, request_id: caller.request_id, item_id: item['id'],
                    path: entry['path'], entry: entry)
      end

      # The reply of request_id ended without a message.
      def close(request_id)
        return unless request_id

        @lock.synchronize do
          @closed[request_id] = true
          @closed.shift while @closed.size > CLOSED_LIMIT
          @in_flight.delete(request_id)
        end
      end

      def closed?(request_id)
        @lock.synchronize { @closed.key?(request_id) }
      end

      # The reply of request_id was recorded.
      def done(request_id)
        @lock.synchronize { @in_flight.delete(request_id) }
      end

      # Whether the reply of request_id still runs (its message may come).
      def in_flight?(request_id)
        @lock.synchronize { @in_flight.key?(request_id) }
      end

      # For tests.
      def reset!
        @lock.synchronize do
          @closed.clear
          @in_flight.clear
        end
      end
    end
  end
end

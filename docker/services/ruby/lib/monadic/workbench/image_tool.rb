# frozen_string_literal: true

require 'base64'
require 'json'
require 'securerandom'
require_relative 'board'
require_relative 'board_edit'
require_relative 'edit_inputs'
require_relative 'sent'
require_relative 'image_check'
require_relative 'caller'
require_relative 'job_output'
require_relative 'offer'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'
require_relative '../utils/tool_image_utils'

module Monadic
  module Workbench
    # What the image tools of a chat (each provider's) share, apart from
    # calling their provider: whether a tool may run for the chat, which
    # image an edit starts from, and a run of a generator whose image goes
    # to the chat's workbench. Calls no provider API.
    module ImageTool
      # The edit's images: paths in the shared folder, the
      # bytes of a board image (board_input), or the original and the drawn
      # reference of a whiteboard drawn on an image (inputs, in that order:
      # BoardEdit::Input).
      Source = Struct.new(:images, :board_input, :inputs, keyword_init: true) do
        def drawn? = !inputs.nil?
      end

      # Said to the image model before the user's words when an edit is
      # given the original and the drawn reference.
      DRAWN_NOTE = 'Edit the first image. The second image is the same picture with marks the user drew on it, ' \
                   'showing what to change and where; leave the marks themselves out of the result. '

      PENDING = 'The whiteboard is being made an image (it left Now): try again once it is one; nothing is edited.'

      # An edit that cannot start: the message says why.
      class NoSource < StandardError; end

      module_function

      # Why a tool may not run for this reply, or nil. Nothing is made
      # without the chat to put it in (never saved elsewhere).
      def refusal(workbench)
        return '❌ Image generation failed: the chat this reply is for could not be identified.' unless workbench

        nil
      end

      # Which images an edit starts from, in this order: the user's uploads
      # in this turn (a mask kept with a message of an older chat is not an
      # image to edit); images of the
      # shared folder the user named in their message (a name at the top of
      # the shared folder, or a path in it such as an image of a chat
      # folder); the image the asking tab has selected on the workbench (a
      # generated one, or an image of the shared folder opened there); the
      # image that came last on the workbench (read from the shared folder
      # and checked: one that changed or is gone stops the edit); the
      # uploads in the last user message. Every image of the chosen kind is found, or the edit stops:
      # nothing else is edited in its place. Names the model passed count
      # only as the user's own words name them. A whiteboard drawn on an
      # image (named by item, or selected) gives its picture and the board
      # as drawn (BoardEdit). item (an item of the work screen, by its id)
      # comes before all of these. Raises NoSource when there is nothing to
      # edit.
      def edit_source(session:, workbench:, images:, item: nil)
        return item_source(workbench, item.to_s, images) unless item.nil? || item.to_s.empty?

        named = Array(images).filter_map do |img|
          upload = upload_name(img)
          upload ? File.basename(upload.to_s) : (img.is_a?(String) ? shared_name(img) : nil)
        end.reject(&:empty?)
        last_user = Array(session && session[:messages]).reverse.find { |m| m['role'] == 'user' }
        user_text = last_user ? last_user['text'].to_s : ''
        last_uploads = last_user && last_user['images']

        source = upload_source(session, session && session[:parameters] && session[:parameters]['images'])
        return source if source

        if !named.empty? && named.all? { |n| named_in_text?(user_text, n) }
          missing = named.reject { |name| shared_image?(name) || (!name.include?('/') && restore_upload(session, name)) }
          raise NoSource, "❌ The image you named was not found: #{missing.join(', ')}" unless missing.empty?

          return Source.new(images: named)
        end

        selected = selected_image(workbench)
        return selected if selected

        latest = workbench && Board.existing(workbench.chat_id)&.latest_image
        if latest
          begin
            return Source.new(board_input: Board.for(workbench.chat_id).image_input(latest['id']))
          rescue Board::Refused => e
            raise NoSource, "❌ #{e.message.sub(/\A./, &:upcase)}: it is not edited, and no other image is used in its place."
          end
        end

        source = upload_source(session, last_uploads)
        return source if source

        raise NoSource, '❌ No image to edit: there is no image in the work screen, and none was uploaded or named.'
      end

      # The item of the work screen item_id names: an image (read at the
      # version it has now, selected or not), or a whiteboard drawn on an
      # image (its picture and the board as the tab draws it: only one the
      # tab shows). Nothing else, and no other image in its place.
      def item_source(workbench, item_id, images)
        raise NoSource, '❌ Name an item of the work screen or images, not both.' if Array(images).any?

        board = workbench && Board.existing(workbench.chat_id)
        item = board&.item(item_id) or raise NoSource, '❌ That item is not on the work screen now: nothing is edited.'
        raise NoSource, "❌ #{Board::PUT_AWAY.sub(/\A./, &:upcase)}: nothing is edited." if item['place'] == 'stash'
        # A whiteboard that left Now is made an image by a page first: nothing
        # is edited in its place meanwhile.
        raise NoSource, "❌ #{PENDING}" if board.image_pending(item['id'])
        return drawn_source(workbench, item_id) if BoardEdit.whiteboard?(item)
        unless item['artifact'] || item.dig('file', 'preview') == 'image'
          raise NoSource, '❌ That item is not an image or a whiteboard drawn on one: nothing is edited.'
        end

        Source.new(board_input: input_of(board, item))
      rescue Board::Refused, Artifact::Missing, Artifact::Changed, Artifact::NotAllowed, FileItem::Busy => e
        raise NoSource, "❌ That item cannot be edited (#{e.message}): no other image is used in its place."
      end

      # The image of the work screen's item item_id, for a tool that starts
      # from one (a video's first frame, music made from it): read at the
      # version it has now, { content_type:, bytes: }. An item that is no
      # image is refused, with no other image in its place.
      def item_image(workbench, item_id)
        board = workbench && Board.existing(workbench.chat_id)
        item = board&.item(item_id) or raise NoSource, '❌ That item is not on the work screen now: nothing is made from it.'
        raise NoSource, "❌ #{Board::PUT_AWAY.sub(/\A./, &:upcase)}: nothing is made from it." if item['place'] == 'stash'
        unless item['artifact'] || item.dig('file', 'preview') == 'image'
          raise NoSource, '❌ That item is not an image: nothing is made from it.'
        end

        input_of(board, item)
      rescue Board::Refused, Artifact::Missing, Artifact::Changed, Artifact::NotAllowed, FileItem::Busy => e
        raise NoSource, "❌ That image cannot be read (#{e.message}): no other image is used in its place."
      end

      # The picture and the drawn reference of the whiteboard (item_id, or
      # the one the tab shows).
      def drawn_source(workbench, item_id = nil)
        Source.new(inputs: BoardEdit.inputs(workbench, item_id: item_id))
      rescue BoardEdit::NoSource => e
        raise NoSource, "❌ #{e.message.sub(/\A./, &:upcase)}: nothing is edited."
      end

      # An image item's bytes, read now and checked.
      def input_of(board, item)
        return board.image_input(item['id']) if item['artifact']

        read = board.file_read(item['id'], sha256: item.dig('file', 'sha256'))
        image_input(read[:bytes], item.dig('file', 'path')).merge(id: item['id'], name: item.dig('file', 'name'))
      end

      # The prompt sent with the edit: for the original and its drawn
      # reference, what each is comes first.
      def edit_prompt(source, prompt)
        source&.drawn? ? DRAWN_NOTE + prompt.to_s : prompt
      end

      # The image the caller's tab has selected on the work screen, as the
      # input of a run (its bytes, read now and checked): a generated image,
      # or an image of the shared folder opened there. nil when the tab
      # selects nothing, something that is not an image, or its connection
      # is gone: the latest image is used then, as before. An image that was
      # selected and then is gone, changed or no longer selected while it is
      # read stops the edit: no other image is used in its place.
      def selected_image(workbench)
        board = workbench && Board.existing(workbench.chat_id)
        target = board&.look_target(tab: workbench.tab, generation: workbench.generation)
        return nil unless target.is_a?(Board::Target)

        item = target.item
        return drawn_source(workbench) if BoardEdit.whiteboard?(item)

        file_image = item['kind'] == 'file' && item.dig('file', 'preview') == 'image'
        return nil unless item['artifact'] || file_image

        input = input_of(board, item)
        unless board.still_selected?(tab: workbench.tab, generation: workbench.generation, item: item, serial: target.serial)
          raise NoSource, '❌ The image selected in the work screen changed while it was read: it is not edited.'
        end

        Source.new(board_input: input)
      rescue Board::Refused, Artifact::Missing, Artifact::Changed, Artifact::NotAllowed, FileItem::Busy => e
        raise NoSource, "❌ The image selected in the work screen cannot be edited (#{e.message}): no other image is used in its place."
      end

      # The images of a list of uploads, as files of the shared folder; nil
      # when the list has none. Attachments that are not images, and masks
      # kept with messages of older chats, are left out. Raises NoSource
      # when an image cannot be found.
      def upload_source(session, list)
        plain = Array(list).select { |upload| upload.is_a?(Hash) }
                           .reject { |upload| mask_upload?(upload) }.select { |upload| image_upload?(upload) }
        return nil if plain.empty?

        found = plain.map { |upload| [upload_name(upload) || '(unnamed)', stored_upload(upload)] }
        missing = found.reject(&:last).map(&:first)
        raise NoSource, "❌ The image you uploaded could not be read: #{missing.join(', ')}" unless missing.empty?

        Source.new(images: found.map(&:last))
      end

      def mask_upload?(upload)
        upload.is_a?(Hash) && (upload['is_mask'] == true || upload_name(upload).to_s.start_with?('mask__'))
      end

      # Whether an upload is an image (not a PDF or another document), by
      # its type or its data, when it gives them.
      def image_upload?(upload)
        type = upload['type'].to_s
        return type.start_with?('image/') unless type.empty?

        data = upload['data'].to_s
        data.start_with?('data:') ? data.start_with?('data:image/') : true
      end

      # An upload as a file of the shared folder: its data written there, or
      # the file it was kept as. Its name, or nil.
      def stored_upload(upload)
        name = upload_name(upload)
        data = upload['data'].to_s
        return name && write_upload(data, name) if data.start_with?('data:')

        kept = data.start_with?('/data/') ? File.basename(data) : name
        kept && shared_image?(kept) ? File.basename(kept) : nil
      end

      # Runs a generator for the reply's chat in a job folder of its own,
      # places the image it made in the chat's folder and puts it on the
      # workbench (Offer): the block gets the
      # job's out/ folder and the paths of its inputs (the board image an
      # edit starts from, given through in/), and returns what the generator
      # said. Returns the Offered image, or what the generator said when it
      # made none. The job folder is removed in every case.
      def run_job(workbench, board_input: nil, drawn: nil)
        sending = work_screen_inputs(board_input, drawn)
        begin
          Sent.check_room!(workbench.chat_id, sending.sum { |input| input[:bytes].bytesize })
        rescue Sent::Full => e
          return "❌ Image generation failed: #{e.message}."
        end
        job = JobOutput.make(workbench.chat_id)
        begin
          inputs = []
          if board_input
            ext = board_input[:content_type].split('/').last.sub('jpeg', 'jpg')
            inputs << JobOutput.put_input!(job, "input.#{ext}", board_input[:bytes])
          end
          # The original first, then the drawn reference.
          Array(drawn).each_with_index do |input, i|
            ext = input.content_type.split('/').last.sub('jpeg', 'jpg')
            inputs << JobOutput.put_input!(job, "input-#{i + 1}-#{input.role}.#{ext}", input.bytes)
          end
          said = yield JobOutput.out_dir(job), inputs
          keep_sent(workbench, sending, said)
          return said if JobOutput.files(job).empty?

          # An edit of a generated image keeps where it came from; one of a
          # file of the shared folder does not (as with a named file).
          derived_from = board_input&.dig(:artifact_id) && { artifact_id: board_input[:artifact_id], sha256: board_input[:sha256] }
          Offer.image(workbench, job, derived_from: derived_from).tap { |offered| offered.notice = notice_in(said) }
        rescue Board::PlacedOnly => e
          # Not a failed generation: the image is in the shared folder.
          "The image was saved in the shared folder as `#{e.path}`, but it is not shown in the work screen: #{e.message}"
        rescue Board::Refused, ImageCheck::Refused, JobOutput::Refused => e
          "❌ Image generation failed: #{e.message}"
        ensure
          begin
            JobOutput.remove(job)
          rescue StandardError => e
            # Left for later; what the run gave is what is answered.
            Monadic::Utils::ExtraLogger.log { "[Workbench] Job folder not removed: #{e.class}: #{e.message}" }
          end
        end
      end

      # The images of the work screen an edit sends (a board image, or a
      # whiteboard's picture and the reference drawn on it), with their roles.
      def work_screen_inputs(board_input, drawn)
        out = []
        out << { role: 'original', bytes: board_input[:bytes], content_type: board_input[:content_type] } if board_input
        Array(drawn).each { |input| out << { role: input.role, bytes: input.bytes, content_type: input.content_type } }
        out
      end

      # When the generator handed its request to the provider (said:
      # its JSON says posted), the images of the work screen it sent are
      # kept as sent and recorded for the reply's message (EditInputs),
      # taken or refused as the generator says; otherwise nothing is.
      def keep_sent(workbench, sending, said)
        return if sending.empty?

        result = JSON.parse(said.to_s[/\{.*\}/m].to_s)
        return unless result.is_a?(Hash) && result['posted'] == true

        state = result['success'] == true ? 'sent' : 'refused'
        call = "e_#{SecureRandom.hex(8)}"
        app_name = workbench.session.respond_to?(:[]) ? workbench.session[:parameters]&.dig('app_name') : nil
        sending.each do |input|
          sha256 = Sent.keep!(workbench.chat_id, input[:bytes], input[:content_type], app_name: app_name)
          recorded = EditInputs.add(workbench.request_id, workbench.chat_id, call: call, role: input[:role],
                                                                             sha256: sha256,
                                                                             content_type: input[:content_type], state: state,
                                                                             session: workbench.session)
          Sent.done(workbench.chat_id, [sha256]) unless recorded
        rescue Sent::Refused
          next
        end
      rescue JSON::ParserError
        nil
      end

      # An image of the shared folder as an input sent with a request:
      # read once as a plain file (never through a link) and an image by its
      # leading bytes. Raises NoSource otherwise.
      def shared_input(name)
        relative = shared_name(name)
        raise NoSource, "❌ The image you named could not be read: #{name}" if relative.empty?

        bytes = Monadic::Utils::SharedPathGuard.read_bytes!(File.join(shared_folder, relative), limit: ImageCheck::MAX_BYTES)
        image_input(bytes, relative)
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        raise NoSource, "❌ The image you named could not be read: #{relative}"
      end

      # An input the server gave a run (JobOutput.put_input!), for a provider
      # that sends the bytes itself.
      def job_input(path)
        image_input(JobOutput.read_input(path), File.basename(path))
      end

      def image_input(bytes, name)
        type = bytes && Monadic::Utils::ToolImageUtils.image_media_type(bytes)
        raise NoSource, "❌ Not an image that can be sent: #{name}" unless type.to_s.start_with?('image/')

        { content_type: type, bytes: bytes }
      end

      # The longest notice a reply line takes.
      NOTICE_LIMIT = 300

      # What a generator's JSON said the user should know beside the image:
      # its message when it used another model than the one asked for. Only
      # a fixed text of our own generator scripts is meant here, never an
      # error of the provider or a model's output.
      def notice_in(said)
        result = JSON.parse(said.to_s[/\{.*\}/m].to_s)
        notice = result.is_a?(Hash) && result['fallback_from'] ? result['message'] : nil
        notice.is_a?(String) && !notice.strip.empty? ? notice.strip[0, NOTICE_LIMIT] : nil
      rescue JSON::ParserError
        nil
      end

      # Whether text names the file name as a whole, alone or at the end of
      # a path (not as a part of a longer name, such as "cat.png" in
      # "bobcat.png" or "cat.png.bak").
      def named_in_text?(text, name)
        text.to_s.match?(/(?<![A-Za-z0-9_.-])#{Regexp.escape(name)}(?![A-Za-z0-9_-]|\.[A-Za-z0-9])/)
      end

      def upload_name(img)
        img.is_a?(Hash) ? (img['name'] || img['filename'] || img['title']) : nil
      end

      def shared_folder
        Monadic::Utils::Environment.shared_volume
      end

      # A name the user gave for a file of the shared folder, as a path in
      # it: at the top (a name), or below (conversations/.../x.png); /data/
      # in front is taken off. "" for a name that cannot be one.
      def shared_name(name)
        text = name.to_s.strip.delete_prefix('/data/')
        return '' if text.empty? || text.start_with?('/') || text.include?("\0") || text.split('/').include?('..')

        text
      end

      # Whether a plain file of the shared folder has this name (shared_name),
      # reached with no link.
      def shared_image?(name)
        relative = shared_name(name)
        !relative.empty? && !Monadic::Utils::SharedPathGuard.file_stat(File.join(shared_folder, relative)).nil?
      end

      # An upload's data written as a file of the shared folder, never
      # through a link. Its name, or nil.
      def write_upload(data, name)
        return nil unless data.to_s.start_with?('data:image/')

        Monadic::Utils::SharedPathGuard.write_file!(File.join(shared_folder, File.basename(name)),
                                                    Base64.decode64(data.split(',').last))
        File.basename(name)
      end

      # An upload of an earlier turn named name, written to the shared
      # folder; nil when there is none.
      def restore_upload(session, name)
        Array(session && session[:messages]).reverse_each do |message|
          upload = Array(message['images']).find { |img| (n = upload_name(img)) && File.basename(n) == name }
          return write_upload(upload['data'], name) if upload
        end
        nil
      end
    end
  end
end

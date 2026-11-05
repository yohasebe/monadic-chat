# frozen_string_literal: true

require 'base64'
require 'json'
require_relative 'board'
require_relative 'image_check'
require_relative 'caller'
require_relative 'job_output'
require_relative 'offer'
require_relative '../history/policy'
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
      # The edit's images: names of the shared folder (and a mask), or the
      # bytes of a board image (board_input).
      Source = Struct.new(:images, :mask, :board_input, keyword_init: true)

      # An edit that cannot start: the message says why.
      class NoSource < StandardError; end

      module_function

      # Why a tool may not run for this reply, or nil. Nothing is made
      # without the chat to put it in (never saved elsewhere), and nothing
      # of a Private chat is kept.
      def refusal(workbench)
        return '❌ Image generation failed: the chat this reply is for could not be identified.' unless workbench

        policy = Monadic::History::Policy
        if policy.private?(workbench.session) || policy.known_private?(workbench.chat_id)
          return '❌ Image generation is not available in a Private chat: nothing of it may be kept.'
        end

        nil
      end

      # Which images an edit starts from, in this order: the user's uploads
      # in this turn (with the mask the user drew for one of them in the
      # mask editor, an upload named mask__<image>); a mask drawn in the
      # last user message, with that message's uploads; images of the
      # shared folder the user named in their message; the image that came
      # last on the workbench (saved or not); the uploads in the last user
      # message. Every image of the chosen kind is found, or the edit stops:
      # nothing else is edited in its place. Names the model passed count
      # only as the user's own words name them. Raises NoSource when there
      # is nothing to edit.
      def edit_source(session:, workbench:, images:, mask: nil)
        named = Array(images).filter_map { |img| upload_name(img) || (img.is_a?(String) ? img : nil) }
                             .map { |n| File.basename(n.to_s) }.reject(&:empty?)
        last_user = Array(session && session[:messages]).reverse.find { |m| m['role'] == 'user' }
        user_text = last_user ? last_user['text'].to_s : ''
        last_uploads = last_user && last_user['images']

        source = upload_source(session, session && session[:parameters] && session[:parameters]['images'], mask)
        return source if source
        return upload_source(session, last_uploads, mask) if Array(last_uploads).any? { |u| mask_upload?(u) }

        if !named.empty? && named.all? { |n| named_in_text?(user_text, n) }
          missing = named.reject { |name| shared_image?(name) || restore_upload(session, name) }
          raise NoSource, "❌ The image you named was not found: #{missing.join(', ')}" unless missing.empty?

          return Source.new(images: named, mask: mask)
        end

        latest = workbench && Board.existing(workbench.chat_id)&.latest_image
        if latest
          raise NoSource, '❌ A mask applies to an uploaded or named image, not to the image in the work screen.' if mask

          return Source.new(board_input: Board.for(workbench.chat_id).candidate_input(latest['id']))
        end

        source = upload_source(session, last_uploads, mask)
        return source if source

        raise NoSource, '❌ No image to edit: there is no image in the work screen, and none was uploaded or named.'
      end

      # The images of a list of uploads, as files of the shared folder, with
      # the mask drawn for one of them (that image first); nil when the list
      # has neither. Attachments that are not images are left out. Raises
      # NoSource when an image cannot be found.
      def upload_source(session, list, mask)
        list = Array(list).select { |upload| upload.is_a?(Hash) }
        editor_mask = list.find { |upload| mask_upload?(upload) }
        plain = list.reject { |upload| mask_upload?(upload) }.select { |upload| image_upload?(upload) }
        return nil if plain.empty? && !editor_mask

        found = plain.map { |upload| [upload_name(upload) || '(unnamed)', stored_upload(upload)] }
        if editor_mask
          mask = upload_name(editor_mask)
          target = File.basename((editor_mask['mask_for'] || mask.delete_prefix('mask__')).to_s)
          found.reject! { |name, _| File.basename(name) == target }
          found.unshift([target, shared_image?(target) || restore_upload(session, target) ? target : nil])
        end
        missing = found.reject(&:last).map(&:first)
        raise NoSource, "❌ The image you uploaded could not be read: #{missing.join(', ')}" unless missing.empty?

        Source.new(images: found.map(&:last), mask: mask)
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

      # Runs a generator for the reply's chat in a job folder of its own and
      # puts the image it made on the workbench (Offer): the block gets the
      # job's out/ folder and the paths of its inputs (the board image an
      # edit starts from, given through in/), and returns what the generator
      # said. Returns the Offered image, or what the generator said when it
      # made none. The job folder is removed in every case.
      def run_job(workbench, board_input: nil)
        job = JobOutput.make(workbench.chat_id)
        begin
          inputs = []
          if board_input
            ext = board_input[:content_type].split('/').last.sub('jpeg', 'jpg')
            inputs << JobOutput.put_input!(job, "input.#{ext}", board_input[:bytes])
          end
          said = yield JobOutput.out_dir(job), inputs
          return said if JobOutput.files(job).empty?

          derived_from = board_input && { id: board_input[:id], sha256: board_input[:sha256] }
          Offer.image(workbench, job, derived_from: derived_from).tap { |offered| offered.notice = notice_in(said) }
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

      # An image of the shared folder as an input sent with a request:
      # read once as a plain file (never through a link) and an image by its
      # leading bytes. Raises NoSource otherwise.
      def shared_input(name)
        path = File.join(shared_folder, File.basename(name.to_s))
        bytes = Monadic::Utils::SharedPathGuard.read_bytes!(path, limit: ImageCheck::MAX_BYTES)
        image_input(bytes, File.basename(name.to_s))
      rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
        raise NoSource, "❌ The image you named could not be read: #{File.basename(name.to_s)}"
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

      def shared_image?(name)
        File.exist?(File.join(shared_folder, File.basename(name.to_s)))
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

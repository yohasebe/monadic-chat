# frozen_string_literal: true

require "json"
require "shellwords"
require_relative "environment"
require_relative "shared_path_guard"
require_relative "../workspace"
require_relative "../workbench/chat_output"

module Monadic
  module Utils
    # The features measured from an audio or MIDI file of the shared folder
    # (tempo, key, time signature, chords, sections): one run of the analyzer
    # in the Python container, for every app that offers it. The app that
    # includes this says the result in its own words.
    module MusicFeatures
      # Audio is measured with the optional Music Analysis package (librosa +
      # madmom). MIDI is read with pretty_midi, and the analyzer itself says
      # when that is missing.
      AUDIO_EXTENSIONS = %w[mp3 mpeg m4a mp4 wav ogg flac].freeze
      # The shared folder as the Python container sees it, in either mode.
      SHARED_FOLDER = Environment::CONTAINER_DATA_PATH
      PACKAGE_NEEDED = "❌ Measuring the features of an audio file needs the optional Music Analysis package " \
                       "(librosa + madmom). Turn it on under Actions → Install Options and rebuild " \
                       "the Python container."

      # The music file a tool was given: a file attached to the chat
      # (attachment_id) or a file of the shared folder (file_path), as
      # { relative:, absolute: } (its path in the shared folder, and where
      # this process reads it), or { error: }. Audio is shown on the work
      # screen of the reply, so the user can listen while reading.
      def music_file(file_path: nil, attachment_id: nil, session: nil, workbench: nil)
        id = attachment_id.to_s.strip
        # Models sometimes pass the attachment id as the file name.
        id = file_path.to_s.strip if id.empty? && Monadic::Workspace::Ids.valid?(:attachment, file_path.to_s.strip)
        relative, absolute =
          if id.empty?
            # The shared folder's own boundary: no path that leaves it, by
            # its name or through a link.
            given = file_path.to_s.strip
            seen = SharedPathGuard.command_path(given, container: "python", must_exist: false)
            return { error: "Give the attachment_id of an attached file, or the path of a file in the shared folder." } unless seen

            [seen.delete_prefix("#{SHARED_FOLDER}/"), SharedPathGuard.resolve_in_shared(given, must_exist: false)]
          else
            record = resolve_audio_attachment(id, session)
            [record[:relative_path], record[:path]]
          end
        if AUDIO_EXTENSIONS.include?(File.extname(relative).delete_prefix(".").downcase)
          Monadic::Workbench::ChatOutput.show(relative, workbench)
        end
        { relative: relative, absolute: absolute }
      rescue Monadic::Workspace::Attachments::Unusable => e
        { error: e.message }
      end

      # The analyzer's result for a file music_file found ("success" => true,
      # with the features), or "success" => false with "error";
      # "package_needed" => true when the Music Analysis package is off.
      def measure_music_features(file)
        extension = File.extname(file[:relative]).delete_prefix(".").downcase
        if AUDIO_EXTENSIONS.include?(extension) && !MusicFeatures.package_enabled?
          return { "success" => false, "error" => PACKAGE_NEEDED, "package_needed" => true }
        end

        params = JSON.generate({ "file_path" => "#{SHARED_FOLDER}/#{file[:relative]}" })
        command = "python3 /monadic/scripts/music/music_analyzer.py analyze --params #{Shellwords.escape(params)}"
        MusicFeatures.parse(send_command(command: command, container: "python"))
      end

      # The Music Analysis install option, recorded as PYOPT_LIBROSA.
      def self.package_enabled?
        defined?(CONFIG) && CONFIG.respond_to?(:[]) && CONFIG["PYOPT_LIBROSA"].to_s.strip.downcase == "true"
      end

      # The analyzer prints one JSON object, which may have other text
      # around it.
      def self.parse(output)
        return output if output.is_a?(Hash)

        text = output.to_s
        start = text.index("{")
        finish = text.rindex("}")
        return { "success" => false, "error" => "The analyzer gave no result." } unless start && finish && finish > start

        parsed = JSON.parse(text[start..finish])
        parsed.is_a?(Hash) ? parsed : { "success" => false, "error" => "The analyzer gave no result." }
      rescue JSON::ParserError => e
        { "success" => false, "error" => "The analyzer's result could not be read: #{e.message}" }
      end
    end
  end
end

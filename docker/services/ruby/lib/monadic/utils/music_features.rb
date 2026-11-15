# frozen_string_literal: true

require "json"
require "shellwords"
require_relative "environment"

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

      # The analyzer's result ("success" => true, with the features), or
      # "success" => false with "error"; "package_needed" => true when the
      # Music Analysis package is off.
      def measure_music_features(file_path)
        path = MusicFeatures.path_in_shared_folder(file_path)
        return { "success" => false, "error" => "The file must be in the shared folder." } unless path

        extension = File.extname(path).delete_prefix(".").downcase
        if AUDIO_EXTENSIONS.include?(extension) && !MusicFeatures.package_enabled?
          return { "success" => false, "error" => PACKAGE_NEEDED, "package_needed" => true }
        end

        params = JSON.generate({ "file_path" => path })
        command = "python3 /monadic/scripts/music/music_analyzer.py analyze --params #{Shellwords.escape(params)}"
        MusicFeatures.parse(send_command(command: command, container: "python"))
      end

      # The file's path in the Python container: a path in the shared folder,
      # given with or without the folder in front. nil for a path that leaves
      # the folder.
      def self.path_in_shared_folder(file_path)
        relative = file_path.to_s.strip.delete_prefix("#{SHARED_FOLDER}/")
        return nil if relative.empty? || relative.start_with?("/") || relative.split("/").include?("..")

        "#{SHARED_FOLDER}/#{relative}"
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

# frozen_string_literal: true

require 'json'
require_relative '../shell'

module Monadic
  module Utils
    # Checks a video before anything decodes it in full. ffprobe still parses
    # the untrusted file (it is the first program to do so), so it runs in
    # the Python container, without a shell and with a time limit; the file
    # goes on to frame and audio extraction only if what it reports fits:
    #
    # - the container format is the one the extension names,
    # - there is exactly one video stream besides any cover picture, it comes
    #   first (extraction decodes the first video stream), and its codec is
    #   on the list,
    # - the length is above zero and within MAX_SECONDS (the audio of that
    #   length, at the bitrate extraction uses, stays under the 25 MB that
    #   transcription accepts),
    # - the picture is no larger than MAX_DIMENSION on either side.
    module VideoProbe
      MAX_SECONDS = 3000 # 50 minutes
      MAX_DIMENSION = 4096
      PROBE_TIMEOUT = 60

      # Extension -> ffprobe format names it may report.
      FORMATS = {
        '.mp4' => %w[mov mp4], '.m4v' => %w[mov mp4], '.mov' => %w[mov mp4],
        '.webm' => %w[webm matroska], '.mkv' => %w[matroska webm],
        '.avi' => %w[avi],
        '.mpeg' => %w[mpeg], '.mpg' => %w[mpeg]
      }.freeze

      VIDEO_CODECS = %w[h264 hevc vp8 vp9 av1 mpeg4 mpeg2video mpeg1video mjpeg prores theora ffv1].freeze

      class Rejected < StandardError
        attr_reader :reason

        def initialize(reason, message)
          @reason = reason
          super(message)
        end
      end

      module_function

      # container_path: the file as the Python container sees it.
      # Returns { duration:, width:, height:, audio: } or raises Rejected.
      def check!(container_path)
        ext = container_path.to_s.b[/\.[A-Za-z0-9]{1,10}\z/].to_s.downcase
        formats = FORMATS[ext] or raise Rejected.new(:extension, "Videos of type #{ext.empty? ? '(none)' : ext} are not supported. Use #{FORMATS.keys.join(', ')}.")

        argv = ['ffprobe', '-v', 'error', '-print_format', 'json',
                '-show_entries', 'format=format_name,duration:stream=codec_type,codec_name,width,height:stream_disposition=attached_pic',
                container_path]
        stdout, _stderr, status = Monadic::Shell.exec(container: :python, argv: argv, timeout: PROBE_TIMEOUT)
        info = status.success? ? parse(stdout) : nil
        raise Rejected.new(:unreadable, 'The file could not be read as a video.') unless info

        evaluate(info, formats)
      rescue Monadic::Shell::TimedOut
        raise Rejected.new(:unreadable, 'Reading the video took too long; the file may be damaged.')
      end

      def evaluate(info, formats)
        format = info['format'] || {}
        reported = format['format_name'].to_s.split(',')
        raise Rejected.new(:format, "The file's format (#{reported.first || 'unknown'}) does not match its extension.") if (reported & formats).empty?

        # A cover picture is stored as a one-frame video stream; it is not the video.
        videos = Array(info['streams']).select { |s| s['codec_type'] == 'video' }
        moving = videos.reject { |s| s.dig('disposition', 'attached_pic').to_i == 1 }
        raise Rejected.new(:no_video, 'The file has no video track.') if moving.empty?
        # What is checked here must be what extraction decodes: the first video stream.
        unless moving.size == 1 && videos.first.equal?(moving.first)
          raise Rejected.new(:streams, 'Videos with more than one picture track are not supported.')
        end

        video = moving.first
        unless VIDEO_CODECS.include?(video['codec_name'])
          raise Rejected.new(:codec, "Video encoded as #{video['codec_name']} is not supported.")
        end

        duration = Float(format['duration'], exception: false)
        raise Rejected.new(:duration, 'The length of the video could not be read.') unless duration&.finite? && duration.positive?
        if duration > MAX_SECONDS
          raise Rejected.new(:too_long, "The video is #{(duration / 60).ceil} minutes long; videos up to #{MAX_SECONDS / 60} minutes can be analyzed.")
        end

        width = video['width'].to_i
        height = video['height'].to_i
        unless width.between?(1, MAX_DIMENSION) && height.between?(1, MAX_DIMENSION)
          raise Rejected.new(:dimensions, "Videos up to #{MAX_DIMENSION} pixels on each side can be analyzed (this one is #{width}x#{height}).")
        end

        { duration: duration, width: width, height: height,
          audio: Array(info['streams']).any? { |s| s['codec_type'] == 'audio' } }
      end

      def parse(stdout)
        data = JSON.parse(stdout.to_s)
        data.is_a?(Hash) && data['format'].is_a?(Hash) ? data : nil
      rescue JSON::ParserError
        nil
      end
    end
  end
end

# frozen_string_literal: true

require "base64"
require "json"
require "securerandom"
require "fileutils"
require "uri"
require "http"
require_relative "http_client"
require_relative "error_formatter"

module Monadic
  module Utils
    # Video generation with Gemini Omni over the Interactions API, the one
    # place Monadic Chat uses that API (the chat path stays on generateContent).
    #
    # One synchronous request with store: false, so Google keeps no
    # interaction for it. The request is sent once: generation is paid, and a
    # request whose reply never arrived may still have produced a video, so a
    # dropped connection is reported as an unknown outcome instead of being
    # sent again. A video counts as made only once its file is saved.
    #
    # Live-checked 2026-10-17: a reply in about 25 s; response_format.duration
    # "4s" and "8s" give exactly that length at 1280x720 with audio; an image
    # given with <FIRST_FRAME> and task image_to_video becomes the first frame;
    # a value the model refuses is a 400 with error.message.
    class GeminiOmniVideo
      ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions"
      API_HOST = "generativelanguage.googleapis.com"
      ASPECT_RATIOS = %w[16:9 9:16].freeze
      DURATIONS = (3..10)
      DEFAULT_DURATION = 8
      RESOLUTION = "720p"
      # The time the requests may take, set below the 660 s send_command gives
      # this generator, to leave room for saving and printing the result.
      DEADLINE_SECONDS = 540
      MAX_MESSAGE_CHARS = 500
      MAX_REDIRECTS = 5
      FILE_READY_POLL_SECONDS = 2
      IMAGE_TYPES = { ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg", ".webp" => "image/webp" }.freeze
      MAX_IMAGE_BYTES = 10 * 1024 * 1024

      # Raised when the deadline passes while a reply is being read.
      class DeadlineExceeded < StandardError; end

      def self.api_origin?(uri)
        uri = URI.parse(uri.to_s) unless uri.respond_to?(:host)
        uri.scheme == "https" && uri.host == API_HOST && uri.port == 443
      rescue URI::InvalidURIError
        false
      end

      def initialize(api_key:, model:, save_dir:, deadline_seconds: DEADLINE_SECONDS)
        @api_key = api_key
        @model = model
        @save_dir = save_dir
        @deadline = monotonic + deadline_seconds
      end

      # image: { data: <bytes>, mime_type: } or nil.
      # Returns a Hash: success, filename and the request's settings, or
      # success false with an error kind and a message for the user.
      def generate(prompt:, image: nil, aspect_ratio: "16:9", duration: DEFAULT_DURATION, negative_prompt: nil)
        problem = invalid_input(prompt, image, aspect_ratio, duration)
        return failure(:invalid_input, problem) if problem

        response = post(request_body(prompt, image, aspect_ratio, duration.to_i, negative_prompt))
        return response if response[:success] == false

        video = video_part(response[:json])
        return video if video[:success] == false

        bytes = video_bytes(video)
        return bytes if bytes.is_a?(Hash)

        filename = save(bytes)
        { success: true, filename: filename, model: @model, aspect_ratio: aspect_ratio, duration: duration.to_i,
          resolution: RESOLUTION, mode: image ? "image_to_video" : "text_to_video" }
      rescue SystemCallError, IOError => e
        failure(:save_failed, "The video was generated but could not be saved: #{e.message}")
      end

      private

      def invalid_input(prompt, image, aspect_ratio, duration)
        return "A prompt is required." if prompt.to_s.strip.empty?
        return "Aspect ratio must be one of #{ASPECT_RATIOS.join(', ')}." unless ASPECT_RATIOS.include?(aspect_ratio.to_s)
        return "Duration must be a whole number of seconds from #{DURATIONS.min} to #{DURATIONS.max}." unless duration.to_s.match?(/\A\d+\z/) && DURATIONS.cover?(duration.to_i)
        return nil unless image

        return "The image must be PNG, JPEG or WebP." unless IMAGE_TYPES.value?(image[:mime_type])
        return "The image is larger than #{MAX_IMAGE_BYTES / 1024 / 1024} MB." if image[:data].bytesize > MAX_IMAGE_BYTES

        nil
      end

      def request_body(prompt, image, aspect_ratio, duration, negative_prompt)
        text = prompt.to_s.strip
        # Omni takes no negative prompt parameter; what to avoid goes in the prompt.
        text += "\n\nAvoid: #{negative_prompt.to_s.strip}" unless negative_prompt.to_s.strip.empty?
        body = {
          model: @model,
          response_format: { type: "video", aspect_ratio: aspect_ratio, resolution: RESOLUTION, duration: "#{duration}s" },
          store: false, background: false, stream: false
        }
        if image
          body[:input] = [
            { type: "image", data: Base64.strict_encode64(image[:data]), mime_type: image[:mime_type] },
            { type: "text", text: "<FIRST_FRAME> Use this image as the starting frame. #{text}" }
          ]
          body[:generation_config] = { video_config: { task: "image_to_video" } }
        else
          body[:input] = text
        end
        body
      end

      def post(body)
        return failure(:deadline, "Time ran out before the request was sent; nothing was generated.") if expired?

        text, status = begin
          response = HttpClient.deadline(remaining)
                               .headers("x-goog-api-key" => @api_key, "Content-Type" => "application/json")
                               .post(ENDPOINT, json: body)
          # The reply, a video included, is read here: a break while reading
          # it is as unknown as one before it.
          [read_body(response), response.status]
        rescue HTTP::ConnectionError => e
          # Only a refused connection or a name that does not resolve means
          # nothing was sent; a connection that broke later may have been
          # charged for a video.
          return failure(:unreachable, "Gemini could not be reached: #{e.message}") if e.message.match?(/refused|getaddrinfo|nodename|resolve/i)

          return unknown_outcome(e)
        rescue HTTP::TimeoutError, HTTP::Error, OpenSSL::SSL::SSLError, IOError, SystemCallError, DeadlineExceeded => e
          return unknown_outcome(e)
        end

        json = parse_json(text)
        unless status.success?
          kind = status.code.to_i >= 500 ? :provider_error : :rejected
          return failure(kind, "Gemini refused the request (HTTP #{status.code}): #{message_from(json, status.code)}")
        end
        return failure(:invalid_reply, "Gemini's reply could not be read.") unless json.is_a?(Hash)

        state = json["status"].to_s
        unless state == "completed"
          detail = Array(json["errors"]).map { |e| e.is_a?(Hash) ? e["message"] : e }.compact.join("; ")
          detail = "the request ended with status #{state.empty? ? 'unknown' : state}" if detail.empty?
          return failure(:not_completed, "Gemini did not produce a video: #{clean(detail)}")
        end

        { json: json }
      end

      # The video of the first model_output step (the reply also holds thought
      # and, by some revisions, user_input steps).
      def video_part(json)
        parts = Array(json["steps"]).select { |s| s.is_a?(Hash) && s["type"] == "model_output" }
                                    .flat_map { |s| Array(s["content"]) }
                                    .select { |c| c.is_a?(Hash) && c["type"] == "video" }
        return failure(:no_video, "Gemini's reply held no video.") if parts.empty?

        parts.first
      end

      def video_bytes(video)
        bytes = if video["data"].to_s != ""
                  begin
                    Base64.strict_decode64(video["data"].to_s)
                  rescue ArgumentError
                    return failure(:invalid_video, "Gemini's video data could not be decoded.")
                  end
                elsif video["uri"].to_s != ""
                  download(video["uri"].to_s)
                else
                  return failure(:no_video, "Gemini's reply held no video data.")
                end
        return bytes if bytes.is_a?(Hash)
        # An MP4 file has "ftyp" after its first box size.
        return failure(:invalid_video, "Gemini's video is not an MP4 file.") unless bytes.bytesize > 12 && bytes.byteslice(4, 4) == "ftyp"

        bytes
      end

      # The key goes to Google's API host only; a download elsewhere is refused.
      # A Files API address is downloaded once the file is ACTIVE.
      def download(uri)
        return failure(:invalid_reply, "Gemini returned a video address outside its API.") unless self.class.api_origin?(uri)

        not_ready = wait_until_file_active(uri)
        return not_ready if not_ready

        response = get_following_redirects(uri)
        return failure(:download_failed, "The video could not be downloaded (HTTP #{response.status.code}).") unless response.status.success?

        read_body(response)
      rescue URI::InvalidURIError
        failure(:invalid_reply, "Gemini returned an invalid video address.")
      rescue DeadlineExceeded
        failure(:download_failed, "The video was generated, but time ran out while downloading it.")
      rescue HTTP::Error, OpenSSL::SSL::SSLError, IOError, SystemCallError => e
        failure(:download_failed, "The video could not be downloaded: #{e.class.name.split('::').last}.")
      end

      # A download may redirect to storage. Each hop is a request of its own,
      # with the time left then (a redirect followed by the client would get
      # the whole budget again) and the key only while on the API host.
      def get_following_redirects(uri)
        url = uri
        MAX_REDIRECTS.succ.times do
          raise DeadlineExceeded if expired?

          headers = self.class.api_origin?(url) ? { "x-goog-api-key" => @api_key } : {}
          response = HttpClient.deadline(remaining).headers(headers).get(url)
          location = response.headers && response.headers["Location"]
          return response unless [301, 302, 303, 307, 308].include?(response.status.code.to_i) && location

          read_body(response) # the redirect's own body, within the deadline
          url = URI.join(url, location.to_s).to_s
          raise URI::InvalidURIError, "a redirect to #{URI.parse(url).scheme}" unless URI.parse(url).scheme == "https"
        end
        raise HTTP::Redirector::TooManyRedirectsError
      end

      # files/NAME:download -> files/NAME, polled until its state is ACTIVE.
      # nil when ready (or when the address is not a Files API one).
      def wait_until_file_active(uri)
        match = URI.parse(uri).path.to_s.match(%r{\A(/v1beta/files/[^/:]+):download\z})
        return nil unless match

        meta_url = "https://#{API_HOST}#{match[1]}"
        loop do
          raise DeadlineExceeded if expired?

          response = HttpClient.deadline(remaining).headers("x-goog-api-key" => @api_key).get(meta_url)
          return nil unless response.status.success? # no metadata: try the download itself

          state = parse_json(read_body(response)).to_h["state"].to_s
          return nil if state == "ACTIVE" || state.empty?
          return failure(:download_failed, "The generated video file could not be prepared (state #{state}).") if state == "FAILED"

          sleep([FILE_READY_POLL_SECONDS, @deadline - monotonic].min.clamp(0, FILE_READY_POLL_SECONDS))
        end
      end

      # The body, read in pieces so the deadline also bounds a slow reply.
      def read_body(response)
        body = response.body
        return body.to_s unless body.respond_to?(:readpartial)

        buffer = +""
        loop do
          raise DeadlineExceeded if expired?

          chunk = body.readpartial
          break if chunk.nil?

          buffer << chunk
        rescue EOFError
          break
        end
        buffer
      end

      # Written to a file of its own, then published under a new name with a
      # hard link, which fails rather than replace a file that is already
      # there. Only the file this call created is removed.
      # Not bounded by the deadline: the video is already paid for, so it is
      # saved rather than dropped; the deadline is set below the caller's limit
      # to leave room for this.
      def save(bytes)
        FileUtils.mkdir_p(@save_dir)
        3.times do
          filename = "gemini_omni_#{Time.now.strftime('%Y%m%d_%H%M%S')}_#{SecureRandom.hex(4)}.mp4"
          final = File.join(@save_dir, filename)
          partial = File.join(@save_dir, ".#{filename}.part")
          created = false
          begin
            File.open(partial, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |f|
              created = true
              f.write(bytes)
            end
            File.link(partial, final)
            return filename
          rescue Errno::EEXIST
            next # this name is taken (the partial or the final one); draw another
          rescue Errno::EPERM, Errno::ENOTSUP, Errno::EXDEV, Errno::ENOSYS, Errno::EOPNOTSUPP => e
            # A file system without hard links cannot publish without the
            # risk of replacing a file, so the video is not saved there
            # (hard links work on the Docker Desktop virtiofs mount).
            raise IOError, "the shared folder does not support hard links (#{e.class.name.split('::').last})"
          ensure
            File.delete(partial) if created && File.exist?(partial)
          end
        end
        raise Errno::EEXIST, "no free file name in #{@save_dir}"
      end

      def parse_json(text)
        JSON.parse(text)
      rescue JSON::ParserError
        nil
      end

      # The provider's message, never its raw reply.
      def message_from(json, code)
        error = json.is_a?(Hash) ? json["error"] : nil
        message = error.is_a?(Hash) ? error["message"] : error
        message.to_s.strip.empty? ? "no message (HTTP #{code})" : clean(message.to_s)
      end

      # A provider message may quote what it was sent: data URLs and long
      # base64 runs are taken out, identifiers scrubbed, the length capped.
      def clean(text)
        text = text.to_s.gsub(%r{data:[\w/.+-]+;base64,[A-Za-z0-9+/=]+}, "[data omitted]")
                   .gsub(%r{[A-Za-z0-9+/]{120,}={0,2}}, "[data omitted]")
        text = ErrorFormatter.scrub_identifiers(text)
        text.length > MAX_MESSAGE_CHARS ? "#{text[0, MAX_MESSAGE_CHARS]}…" : text
      end

      def unknown_outcome(error)
        failure(:unknown_outcome, "The request was sent but no reply arrived (#{error.class.name.split('::').last}). " \
                                  "A video may still have been generated and charged; it was not requested again.")
      end

      def failure(kind, message)
        { success: false, error: kind.to_s, message: message }
      end

      def expired?
        monotonic >= @deadline
      end

      # Seconds left, the whole of the next request (HttpClient.deadline);
      # callers check expired? first.
      def remaining
        [@deadline - monotonic, 0.1].max
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end

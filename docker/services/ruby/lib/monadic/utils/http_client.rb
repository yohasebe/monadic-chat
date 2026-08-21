# frozen_string_literal: true

require "http"

module Monadic
  module Utils
    # Central timeout policy for outbound HTTP.
    #
    # The `http` gem ships with **no timeout at all** (unlike Net::HTTP's 60s
    # default). A peer that accepts the connection and then goes silent parks
    # the calling thread forever — the failure mode is an unkillable process
    # spinning until someone notices. Every outbound call should therefore be
    # built through one of the helpers below.
    #
    # Two properties of `HTTP#timeout` drive this design:
    #
    # 1. **Never pass a bare Numeric.** `HTTP.timeout(60)` selects
    #    `HTTP::Timeout::Global`, a cap on the entire request, which would
    #    abort a long-but-healthy streaming response. The `connect:/read:/write:`
    #    form selects `HTTP::Timeout::PerOperation` instead.
    #
    # 2. **Always pass `write:` explicitly.** `PerOperation` defaults every
    #    unspecified timeout to **0.25 seconds** (see `WRITE_TIMEOUT` in the
    #    gem). `HTTP.timeout(connect: 30, read: 120)` therefore silently caps
    #    uploads at a quarter second, which breaks base64 images, PDFs, and
    #    audio payloads.
    #
    # Choose a helper by the *shape of the wait*, not by the vendor:
    #
    # - `rest`       — request/response expected to be quick (model lists,
    #                  status polls, resource management).
    # - `generation` — the server blocks while it produces the answer, then
    #                  replies at once. For a non-streaming call the whole
    #                  generation is a single silent read, so `read` has to
    #                  cover the model's full thinking time (LLM completions,
    #                  image/video/audio synthesis).
    # - `streaming`  — chunked responses. `read` is applied per socket read, so
    #                  here it measures the **gap between chunks**, not the
    #                  total duration; a healthy stream keeps resetting it.
    # - `download`   — pulling a large artifact back.
    #
    # Pass explicit keywords to override for a specific call site.
    module HttpClient
      CONNECT_TIMEOUT = 30

      REST_READ = 120
      REST_WRITE = 60

      # Covers a reasoning model at high effort answering in one shot.
      GENERATION_READ = 600
      GENERATION_WRITE = 300

      # Max silence between SSE chunks before we call the stream hung.
      STREAMING_READ = 300
      STREAMING_WRITE = 300

      DOWNLOAD_READ = 300
      DOWNLOAD_WRITE = 60

      module_function

      def rest(connect: CONNECT_TIMEOUT, read: REST_READ, write: REST_WRITE)
        HTTP.timeout(connect: connect, read: read, write: write)
      end

      def generation(connect: CONNECT_TIMEOUT, read: GENERATION_READ, write: GENERATION_WRITE)
        HTTP.timeout(connect: connect, read: read, write: write)
      end

      def streaming(connect: CONNECT_TIMEOUT, read: STREAMING_READ, write: STREAMING_WRITE)
        HTTP.timeout(connect: connect, read: read, write: write)
      end

      def download(connect: CONNECT_TIMEOUT, read: DOWNLOAD_READ, write: DOWNLOAD_WRITE)
        HTTP.timeout(connect: connect, read: read, write: write)
      end
    end
  end
end

require 'shellwords'
require_relative '../utils/progress_broadcaster'
require_relative '../utils/tool_image_utils'
require_relative '../utils/environment'
require_relative '../workbench/chat_output'

module MonadicHelper
  # Adapter for OpenAI function generate_image
  # Accepts keyword args from function call: operation, model, prompt, images, n, size, quality, output_format, background, output_compression
  def generate_image_with_openai(operation:, model:, prompt: nil, images: nil,
                     n: 1, size: "1024x1024", quality: nil,
                     output_format: nil, background: nil, output_compression: nil, input_fidelity: nil,
                     out_dir: nil, job_inputs: [])
    return JSON.generate({ success: false, message: "There is no chat folder to keep the image in." }) unless out_dir

    # Build CLI command
    parts = []
    parts << "image_generator_openai.rb"
    parts << "-o #{Shellwords.shellescape(operation)}"
    parts << "-m #{Shellwords.shellescape(model)}"
    parts << "-p #{Shellwords.shellescape(prompt)}" if prompt
    parts << "-n #{n.to_i}"
    parts << "-s #{Shellwords.shellescape(size)}" if size
    parts << "-q #{Shellwords.shellescape(quality)}" if quality
    parts << "-f #{Shellwords.shellescape(output_format)}" if output_format
    parts << "-b #{Shellwords.shellescape(background)}" if background
    parts << "--compression #{output_compression.to_i}" if output_compression && output_compression.to_i > 0
    parts << "--fidelity #{Shellwords.shellescape(input_fidelity)}" if input_fidelity
    # The run writes in the job folder the server made
    # (Monadic::Workbench::JobOutput), never at the top of the shared folder.
    parts << "--out-dir #{Shellwords.shellescape(out_dir)}"
    Array(job_inputs).each { |path| parts << "--job-input #{Shellwords.shellescape(path)}" }

    # Process image parameters
    if images
      Array(images).each do |img|
        parts << "-i #{Shellwords.shellescape(img)}"
      end
    end

    cmd = parts.join(' ')
    Monadic::Utils::ProgressBroadcaster.with_progress(
      source: "ImageGeneratorOpenAI",
      label: "Generating image with #{model} (#{operation})"
    ) do
      send_command(command: cmd, container: "ruby")
    end
  end


  def generate_image_with_grok(prompt: "", aspect_ratio: nil, quality: nil, operation: "generate", images: nil, image_model: nil,
                              out_dir: nil, job_inputs: [])
    require 'json'
    return JSON.generate({ success: false, message: "There is no chat folder to keep the image in." }) unless out_dir

    parts = ["image_generator_grok.rb", "-p", Shellwords.shellescape(prompt)]
    parts << "-o" << Shellwords.shellescape(operation) if operation && operation != "generate"
    parts << "-a" << Shellwords.shellescape(aspect_ratio) if aspect_ratio
    parts << "-q" << Shellwords.shellescape(quality) if quality
    parts << "-m" << Shellwords.shellescape(image_model) if image_model && !image_model.to_s.strip.empty?
    if images.is_a?(Array)
      images.each { |img| parts << "-i" << Shellwords.shellescape(img) }
    end
    # The run writes in the job folder the server made
    # (Monadic::Workbench::JobOutput), never at the top of the shared folder.
    parts << "--out-dir" << Shellwords.shellescape(out_dir)
    Array(job_inputs).each { |path| parts << "--job-input" << Shellwords.shellescape(path) }
    command = parts.join(' ')

    # Use block form to get detailed stdout/stderr/status for better error reporting
    stdout = ""
    stderr = ""
    status = nil

    Monadic::Utils::ProgressBroadcaster.with_progress(
      source: "ImageGeneratorGrok",
      label: "Generating image with Grok (#{operation})"
    ) do
      send_command(command: command, container: "ruby") do |out, err, stat|
        stdout = out
        stderr = err
        status = stat
      end
    end

    # Extract JSON from stdout
    begin
      json_start = stdout.index('{')
      if json_start
        json_str = stdout[json_start..-1]
        parsed = JSON.parse(json_str)
        return JSON.generate(parsed)
      else
        return JSON.generate({
          success: false,
          message: "No valid JSON response from image generator",
          raw_stdout: stdout,
          raw_stderr: stderr
        })
      end
    rescue JSON::ParserError => e
      return JSON.generate({
        success: false,
        message: "Failed to parse image generator response: #{e.message}",
        raw_stdout: stdout,
        raw_stderr: stderr
      })
    end
  end

  # Adapter for xAI Grok Imagine video generation
  # Accepts keyword args: prompt, duration, aspect_ratio, resolution, image_path
  # In a chat, the video is saved in a run folder of the chat's folder and
  # shown on the work screen; without one, none is made.
  def generate_video_with_grok_imagine(prompt:, duration: nil, aspect_ratio: nil, resolution: nil,
                                       image_path: nil, max_wait: 420, session: nil, workbench: nil, item: nil)
    # Resolve the source image for image-to-video. Uploaded images live in the
    # session as a data URL and must be materialized to a file on the shared
    # volume for the CLI generator. Shared with the Veo path via ToolImageUtils.
    # If an upload exists but can't be materialized, surface the error instead
    # of silently downgrading to text-to-video.
    job = Monadic::Workbench::ChatOutput.run_folder(session: session, workbench: workbench,
                                                    app_name: session&.dig(:parameters, "app_name") || "VideoGeneratorGrok")
    return JSON.generate({ success: false, message: "There is no chat folder to keep the video in." }) unless job

    begin
      image_path = Monadic::Utils::ToolImageUtils.materialize_session_image(session, image_path: image_path, into: job,
                                                                            item: item, workbench: workbench)
    rescue Monadic::Utils::ToolImageUtils::ImageMaterializationError => e
      Monadic::Workbench::ChatOutput.drop_if_empty(job)
      return JSON.generate({ success: false, message: e.message })
    end


    # Build CLI command
    parts = []
    parts << "video_generator_grok.rb"
    parts << "-p" << Shellwords.shellescape(prompt)
    parts << "-d" << duration.to_i.to_s if duration
    parts << "-a" << Shellwords.shellescape(aspect_ratio) if aspect_ratio
    parts << "-r" << Shellwords.shellescape(resolution) if resolution
    parts << "--max-wait" << max_wait.to_i.to_s
    parts << "--out-dir" << Shellwords.shellescape(job[:path])

    if image_path && !image_path.to_s.strip.empty?
      parts << "-i" << Shellwords.shellescape(image_path)
      Monadic::Utils::ToolImageUtils.remember_image(self, session, image_path)
    end

    cmd = parts.join(' ')

    stdout = ""
    stderr = ""
    status = nil

    Monadic::Utils::ProgressBroadcaster.with_progress(
      source: "VideoGeneratorGrok",
      label: "Generating video with Grok Imagine"
    ) do
      send_command(command: cmd, container: "ruby") do |out, err, stat|
        stdout = out
        stderr = err
        status = stat
      end
    end

    begin
      json_start = stdout.index('{')
      if json_start
        json_str = stdout[json_start..-1]
        parsed = JSON.parse(json_str)

        if session && parsed["success"]
          session[:grok_last_video_request_id] = parsed["request_id"] if parsed["request_id"]
          session[:grok_last_video_filename] = parsed["filename"] if parsed["filename"]
        end
        taken = parsed["success"] && Monadic::Workbench::ChatOutput.take(job, parsed["filename"], workbench, "The video")
        parsed["path"], parsed["notice"] = taken.values_at(:path, :notice) if taken

        return JSON.generate(parsed)
      else
        return JSON.generate({
          success: false,
          message: "No valid JSON response from video generator",
          raw_stdout: stdout,
          raw_stderr: stderr
        })
      end
    rescue JSON::ParserError => e
      return JSON.generate({
        success: false,
        message: "Failed to parse video generator response: #{e.message}",
        raw_stdout: stdout,
        raw_stderr: stderr
      })
    ensure
      # Only the file this process wrote from an upload is removed; a name
      # the model or the session gave is never deleted.
      Monadic::Utils::ToolImageUtils.discard_materialized(image_path) if image_path
      Monadic::Workbench::ChatOutput.drop_if_empty(job)
    end
  end

end

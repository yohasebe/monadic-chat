require 'nokogiri'
require 'fileutils'
require 'shellwords'
require_relative '../../lib/monadic/shared_tools/scratch_browser'
require 'cgi'
require 'json'
require 'securerandom'
require_relative '../../lib/monadic/utils/shared_path_guard'

module DrawIOGrapher
  # Template for a valid minimal Draw.io diagram
  MINIMAL_TEMPLATE = <<~XML
    <?xml version="1.0" encoding="UTF-8"?>
    <mxfile host="app.diagrams.net" modified="#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')}" agent="Mozilla/5.0">
      <diagram id="default-diagram" name="Page-1">
        <mxGraphModel dx="1422" dy="762" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" pageWidth="827" pageHeight="1169" math="0" shadow="0">
          <root>
            <mxCell id="0"/>
            <mxCell id="1" parent="0"/>
            <!-- Content goes here -->
          </root>
        </mxGraphModel>
      </diagram>
    </mxfile>
  XML

  def write_drawio_file(content:, filename: "diagram")
    if MonadicSharedTools::BrowserOwner.private_work?
      return "❌ This chat is Private: no diagram file is written and the browser is not used."
    end
    return "❌ Invalid filename" unless filename.is_a?(String)

    # Handle file extension
    filename = "#{filename}.drawio" unless filename.end_with?(".drawio")

    # Use the unified environment module for data directory
    data_dir = Monadic::Utils::Environment.shared_volume

    # Ensure the data directory exists
    unless File.directory?(data_dir)
      begin
        FileUtils.mkdir_p(data_dir)
      rescue StandardError => e
        return "❌ Could not create directory #{data_dir}: #{e.message}"
      end
    end

    filepath = Monadic::Utils::SharedPathGuard.resolve_in_shared(filename, extensions: %w[.drawio], must_exist: false)
    return "❌ Invalid shared file path" unless filepath

    # Validate and repair XML content
    validated_content = validate_and_repair_drawio_xml(content)

    # Write the file synchronously - this keeps the spinner active until completion
    write_file_synchronously(validated_content, filepath, filename, data_dir)
  end

  def preview_drawio(content:, filename: "diagram", session: nil)
    if MonadicSharedTools::BrowserOwner.private_work?
      return "❌ This chat is Private: no diagram file is written and the browser is not used."
    end
    return "❌ Invalid filename" unless filename.is_a?(String)

    # 1. Handle file extension
    filename = "#{filename}.drawio" unless filename.end_with?(".drawio")
    shared_volume = Monadic::Utils::Environment.shared_volume

    # 2. Validate & repair XML
    validated_content = validate_and_repair_drawio_xml(content)

    # 3. Save .drawio file
    drawio_path = Monadic::Utils::SharedPathGuard.resolve_in_shared(filename, extensions: %w[.drawio], must_exist: false)
    return "❌ Invalid shared file path" unless drawio_path
    save_result = write_file_synchronously(validated_content, drawio_path, filename, shared_volume)
    return save_result if save_result.start_with?("❌")

    # 4. Generate preview HTML
    # Unique per call, so concurrent previews never share a file name
    timestamp = "#{Time.now.to_i}_#{SecureRandom.hex(4)}"
    html_filename = "drawio_live_#{timestamp}.html"
    screenshot_filename = "drawio_preview_#{timestamp}.png"
    html_path = Monadic::Utils::SharedPathGuard.resolve_in_shared(html_filename, must_exist: false)
    return "❌ Invalid preview file path" unless html_path
    Monadic::Utils::SharedPathGuard.write_file!(html_path, build_drawio_preview_html(validated_content))

    # 5. A browser session of its own for this preview (ScratchBrowser)
    file_url = "file:///monadic/data/#{html_filename}"
    MonadicSharedTools::ScratchBrowser.with_session(file_url) do |run, start_output|
      start_result = parse_drawio_response(start_output)
      return "❌ Failed to start browser session: #{start_result[:error]}" unless run && start_result[:success]

      # 6. Capture diagram screenshot (waits for SVG to render, resizes to fit)
      ss_result = parse_drawio_response(run.call(%w[--action diagram_screenshot]))

      if ss_result[:success] && ss_result[:screenshot]
        src = Monadic::Utils::SharedPathGuard.resolve_in_shared(ss_result[:screenshot], extensions: %w[.png])
        dst = Monadic::Utils::SharedPathGuard.resolve_in_shared(screenshot_filename, must_exist: false)
        Monadic::Utils::SharedPathGuard.copy_file!(src, dst) if src && dst
      end
    end

    result = {
      success: true,
      filename: filename,
      message: "The file #{filename} has been saved. The preview image is automatically displayed in the chat."
    }
    # Store gallery HTML for server-side display (no _image vision injection)
    if session && File.exist?(File.join(shared_volume, screenshot_filename))
      gallery_html = "<div class=\"generated_image\"><img src=\"/data/#{CGI.escapeHTML(screenshot_filename.to_s)}\" /></div>"
      session[:tool_html_fragments] ||= []
      session[:tool_html_fragments] << gallery_html
    end
    result
  rescue MonadicSharedTools::BrowserOwner::Refused => e
    "❌ #{e.message}"
  rescue StandardError => e
    "❌ Preview generation failed"
  ensure
    # Only this preview's page: another preview may still be loading its own
    if html_filename
      remove_drawio_preview_page(html_filename)
      cleanup_old_drawio_html_files
    end
  end

  private

  def write_file_synchronously(validated_content, filepath, filename, data_dir)
    begin
      resolved = Monadic::Utils::SharedPathGuard.resolve_in_shared(filepath, extensions: %w[.drawio], must_exist: false)
      return "❌ Invalid shared file path" unless resolved

      Monadic::Utils::SharedPathGuard.write_file!(resolved, validated_content)

      # Verify file was written with shorter retry intervals for better UX
      success = false
      max_retrial = 10
      max_retrial.times do |_i|
        sleep 0.2
        if File.exist?(filepath)
          success = true
          break
        end
      end

      # Final verification - ensure file is readable and has content
      if success && File.size(filepath) > 0
        result = "The file #{filename} has been saved successfully to the shared folder (#{data_dir})."
      else
        result = "❌ The file could not be verified at #{filepath}."
      end

      STDOUT.flush
      return result
    rescue StandardError => e
      error_result = "❌ The file could not be written"
      STDOUT.flush
      return error_result
    end
  end

  # Validate and repair Draw.io XML content
  def validate_and_repair_drawio_xml(content)
    begin
      # Convert literal \n string to actual newlines (common issue with OpenAI models)
      content = content.gsub('\\n', "\n") if content.include?('\\n')

      # Parse XML to check validity
      doc = Nokogiri::XML(content) { |config| config.noblanks }

      # Check for basic Draw.io structure
      unless has_valid_drawio_structure?(doc)
        return repair_drawio_xml(content)
      end

      # If we get here, the XML is valid enough
      return content
    rescue => e
      # If there's any parsing error, try to repair
      return repair_drawio_xml(content)
    end
  end

  # Check if the XML has valid Draw.io structure
  def has_valid_drawio_structure?(doc)
    # Check for mxfile root element
    root = doc.root
    return false unless root && root.name == 'mxfile'

    # Check for at least one diagram element
    diagram = root.at_xpath('.//diagram')
    return false unless diagram
    return false unless diagram['id'] && diagram['name']

    # Check for mxGraphModel element
    graph_model = diagram.at_xpath('.//mxGraphModel')
    return false unless graph_model

    # Check for root element in the graph model
    root_cell = graph_model.at_xpath('.//root')
    return false unless root_cell

    # All checks passed
    true
  end

  # Try to repair the Draw.io XML
  def repair_drawio_xml(content)
    # Convert literal \n string to actual newlines (common issue with OpenAI models)
    content = content.gsub('\\n', "\n") if content.include?('\\n')

    # If the content appears to be just cells or partial content
    if content.include?('<mxCell') && !content.include?('<mxfile')
      # Fix common typos/errors in mxCell tags before extraction
      fixed_content = content.gsub(/<mxGeomexCell/, '<mxGeometry></mxCell')
                             .gsub(/<\/mxGeomexCell>/, '</mxGeometry></mxCell>')

      # Use Nokogiri to cleanly extract and fix cells when possible
      begin
        fragment = Nokogiri::XML.fragment("<root>#{fixed_content}</root>")
        cells = fragment.xpath(".//mxCell").map(&:to_xml).join("\n")
      rescue => e
        # Fallback to regex if Nokogiri parsing fails
        cell_pattern = /<mxCell.*?<\/mxCell>/m
        cells = fixed_content.scan(cell_pattern).join("\n")

        # If still no cells found, try more lenient pattern
        if cells.empty?
          cell_pattern = /<mxCell.*?\/mxCell>/m
          cells = fixed_content.scan(cell_pattern).join("\n")
        end
      end

      # If no cells were found, try to salvage any XML-like content
      if cells.empty?
        # Try to extract anything that looks like XML tags
        tag_pattern = /<[^>]+>.*?<\/[^>]+>/m
        cells = fixed_content.scan(tag_pattern).join("\n")
      end

      # Insert into template
      template = MINIMAL_TEMPLATE.dup
      insertion_point = template.index('<!-- Content goes here -->')
      if insertion_point
        template.insert(insertion_point, cells)
      else
        # Fallback to simple replacement
        template.gsub!('<!-- Content goes here -->', cells)
      end

      return template
    elsif content.include?('<diagram') && !content.include?('<mxfile')
      # Content has diagram but no mxfile wrapper
      template = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<mxfile host=\"app.diagrams.net\" modified=\"#{Time.now.utc.strftime('%Y-%m-%dT%H:%M:%S.%3NZ')}\" agent=\"Mozilla/5.0\">\n#{content}\n</mxfile>"
      return template
    elsif !content.include?('<?xml')
      # Missing XML declaration
      return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n#{content}"
    end

    # If we can't repair it in a specific way, return the minimal template
    return MINIMAL_TEMPLATE
  end

  # Parse JSON response from web_navigator.py
  def parse_drawio_response(output)
    json_match = output.to_s.match(/\{.+\}/m)
    return { success: false, error: "No JSON response from navigator" } unless json_match

    JSON.parse(json_match[0], symbolize_names: true)
  rescue JSON::ParserError => e
    { success: false, error: "Failed to parse response: #{e.message}" }
  end

  # Build HTML page for Draw.io viewer rendering
  def build_drawio_preview_html(xml_content)
    # XML → JSON string → HTML attribute escape
    data = {
      highlight: "#0000ff",
      nav: true,
      resize: true,
      xml: xml_content
    }
    data_json = JSON.generate(data)
    escaped_data = CGI.escapeHTML(data_json)

    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <style>
          html, body {
            margin: 0;
            padding: 20px;
            background: white;
          }
        </style>
      </head>
      <body>
        <div class="mxgraph" data-mxgraph="#{escaped_data}"></div>
        <script src="https://viewer.diagrams.net/js/viewer-static.min.js"></script>
      </body>
      </html>
    HTML
  end

  # Pages younger than this may still be loading in another preview
  PREVIEW_PAGE_MAX_AGE = 600

  # Remove the pages previews left behind, older than PREVIEW_PAGE_MAX_AGE
  def cleanup_old_drawio_html_files
    shared_volume = Monadic::Utils::Environment.shared_volume
    Dir.glob(File.join(shared_volume, "drawio_live_*.html")).each do |f|
      # Another preview may remove its own page meanwhile
      next if Time.now - File.lstat(f).mtime < PREVIEW_PAGE_MAX_AGE

      Monadic::Utils::SharedPathGuard.delete_file!(f)
    rescue StandardError
      next
    end
  end

  # Removes the page one preview wrote, once it is done with it
  def remove_drawio_preview_page(html_filename)
    path = File.join(Monadic::Utils::Environment.shared_volume, html_filename)
    (Monadic::Utils::SharedPathGuard.delete_file!(path) rescue nil)
  end
end

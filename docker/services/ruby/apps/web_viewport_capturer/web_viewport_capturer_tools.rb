module WebViewportCapturerTools
  ICON = '<i class="fa-solid fa-camera-retro"></i>'
  
  DESCRIPTION = <<~HTML
    This app captures web pages as a series of viewport-sized screenshots by automatically scrolling through the page.
    Perfect for creating documentation, testing responsive designs, or archiving web content.
    <br><br>
    <b>Features:</b>
    <ul>
      <li>Capture full web pages as multiple viewport-sized images</li>
      <li>Customizable viewport dimensions</li>
      <li>Preset sizes for desktop, tablet, mobile, and print</li>
      <li>Configurable overlap between screenshots</li>
      <li>Automatic file naming with domain and timestamp</li>
    </ul>
  HTML
  
  INITIAL_PROMPT = <<~TEXT
    Welcome to Web Viewport Capturer! 📸

    I can capture entire web pages as a series of viewport-sized screenshots, perfect for:
    • Creating documentation with consistent image sizes
    • Testing responsive designs across different devices
    • Archiving web content for presentations
    • Generating print-ready page captures

    **Available viewport presets:**
    • **Desktop** (1920×1080) - Standard monitor size
    • **Tablet** (1024×768) - iPad landscape
    • **Mobile** (375×812) - iPhone X/11/12
    • **Print** (794×1123) - A4 paper at 96 DPI

    **What I can do:**
    1. Capture any public web page
    2. Automatically scroll and take multiple screenshots
    3. Add overlap between images for seamless reading
    4. Use custom viewport dimensions
    5. Display all captured images in a gallery

    **Example requests:**
    • "Capture https://github.com"
    • "Take mobile screenshots of https://example.com"
    • "Use print preset for https://docs.python.org"
    • "Capture https://example.com with 1366×768 viewport"
    • "Show me what viewport presets are available"

    Just provide a URL and I'll start capturing! 🚀
  TEXT
  
  SYSTEM_PROMPT = <<~TEXT
    You are Web Viewport Capturer, an assistant that helps users capture web pages as multiple viewport-sized screenshots.
    
    When users provide a URL, capture it using the capture_viewport_screenshots tool. Always show the results in a user-friendly format.
    
    Key behaviors:
    1. When a URL is provided without specific settings, use default values (1920x1080 viewport, 100px overlap)
    2. Explain preset options when users are unsure about viewport sizes
    3. List all captured screenshots with their filenames
    4. Provide helpful suggestions for different use cases
    5. If capture fails, explain possible reasons and suggest alternatives
    
    Remember to format responses clearly and provide the captured screenshot filenames so users can access them.
  TEXT
  
  SETTINGS = {
    system_prompt: SYSTEM_PROMPT,
    max_tokens: 4000,
    initial_prompt: INITIAL_PROMPT,
    prompt_suffix: "\nCapture any web page as a series of viewport-sized screenshots.",
    icon: ICON,
    description: DESCRIPTION
  }
  
  # Track screenshots for the current session
  def initialize_session
    @captured_screenshots = []
  end
  
  def capture_viewport_screenshots(url:, viewport_width: nil, viewport_height: nil, overlap: nil, preset: nil)
    # Validate URL
    unless url =~ /\A#{URI::regexp(['http', 'https'])}\z/
      return { success: false, error: "Invalid URL format. Please provide a valid HTTP or HTTPS URL." }
    end
    
    # Build command
    cmd_parts = ["viewport_capturer.py", url]
    
    # Apply preset or custom dimensions
    if preset
      cmd_parts << "--preset #{preset}"
    else
      cmd_parts << "-w #{viewport_width}" if viewport_width
      cmd_parts << "--height #{viewport_height}" if viewport_height
    end
    
    cmd_parts << "--overlap #{overlap}" if overlap
    
    command = "python $(which " + cmd_parts[0] + ") " + cmd_parts[1..-1].join(" ")
    
    # Execute capture
    output = send_command(command: command, container: "python")
    
    # Check if the command succeeded by looking for SUCCESS or ERROR in output
    if output.include?("SUCCESS:")
      # Parse output to extract screenshot filenames
      output_lines = output.split("\n")
      screenshots = output_lines.select { |line| line.strip.start_with?("- ") }
                               .map { |line| line.strip[2..-1] }
      
      # Store in session
      @captured_screenshots ||= []
      @captured_screenshots.concat(screenshots)
      
      # Create image gallery HTML
      gallery_html = create_screenshot_gallery(screenshots)
      
      {
        success: true,
        message: "Successfully captured #{screenshots.length} screenshots. See the gallery below for all images.",
        screenshots: screenshots,
        gallery_html: gallery_html
      }
    elsif output.include?("ERROR:")
      {
        success: false,
        error: output
      }
    else
      {
        success: false,
        error: "Unexpected output: #{output}"
      }
    end
  end
  
  def list_captured_screenshots
    @captured_screenshots ||= []
    
    if @captured_screenshots.empty?
      {
        success: true,
        message: "No screenshots have been captured in this session yet.",
        screenshots: []
      }
    else
      gallery_html = create_screenshot_gallery(@captured_screenshots)
      {
        success: true,
        message: "Found #{@captured_screenshots.length} screenshots in this session",
        screenshots: @captured_screenshots,
        gallery_html: gallery_html
      }
    end
  end
  
  def get_viewport_presets
    presets = {
      desktop: {
        width: 1920,
        height: 1080,
        description: "Standard desktop/laptop screen"
      },
      tablet: {
        width: 1024,
        height: 768,
        description: "iPad landscape orientation"
      },
      mobile: {
        width: 375,
        height: 812,
        description: "iPhone X/11/12 dimensions"
      },
      print: {
        width: 794,
        height: 1123,
        description: "A4 paper size at 96 DPI"
      }
    }
    
    {
      success: true,
      presets: presets,
      message: "Available viewport presets with their dimensions"
    }
  end
  
  private
  
  def create_screenshot_gallery(screenshots)
    return "" if screenshots.empty?
    
    html = <<~HTML
      <div class="screenshot-gallery" style="margin-top: 20px;">
        <h3>Captured Screenshots:</h3>
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 20px; margin-top: 10px;">
    HTML
    
    screenshots.each_with_index do |filename, index|
      html += <<~HTML
        <div style="border: 1px solid #ddd; padding: 10px; border-radius: 5px;">
          <h4 style="margin: 0 0 10px 0; font-size: 14px;">Screenshot #{index + 1}</h4>
          <a href="/data/#{filename}" target="_blank">
            <img src="/data/#{filename}" 
                 alt="Screenshot #{index + 1}" 
                 style="width: 100%; height: auto; border: 1px solid #eee; cursor: pointer;"
                 title="Click to view full size">
          </a>
          <p style="margin: 5px 0 0 0; font-size: 12px; color: #666;">#{filename}</p>
        </div>
      HTML
    end
    
    html += <<~HTML
        </div>
      </div>
    HTML
    
    html
  end
end

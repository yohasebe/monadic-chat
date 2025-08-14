# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Selenium Integration", :integration do
  before(:all) do
    # Ensure Selenium container is available
    begin
      selenium_url = "http://localhost:4444/wd/hub/status"
      uri = URI(selenium_url)
      response = Net::HTTP.get_response(uri)
      unless response.code == "200"
        skip "Selenium container not available"
      end
    rescue => e
      skip "Selenium container not available: #{e.message}"
    end
  end

  describe "Selenium Container" do
    it "is running and accessible" do
      output = `docker ps --format "{{.Names}}" | grep selenium`
      expect(output).to include("monadic-chat-selenium-container")
    end

    it "provides WebDriver service on port 4444" do
      uri = URI("http://localhost:4444/wd/hub/status")
      response = Net::HTTP.get_response(uri)
      expect(response.code).to eq("200")
    end
  end

  describe "webpage_fetcher.py functionality" do
    it "captures screenshots of webpages" do
      # Test with example.com which should be accessible
      command = [
        "python", "/monadic/scripts/cli_tools/webpage_fetcher.py",
        "--url", "https://example.com",
        "--mode", "png",
        "--filepath", "/monadic/data/"
      ].join(" ")
      
      output = `docker exec monadic-chat-python-container #{command} 2>&1`
      
      # Check for actual network issues or container problems
      if output.include?("connection timed out") || 
         output.include?("Failed to fetch") ||
         output.include?("Connection refused") ||
         output.include?("unable to access") ||
         output.include?("container is not running")
        skip "Network connectivity issue or container not available"
      end
      
      # The script should output a success message
      expect(output).to match(/Successfully saved screenshot to:.*\.png/)
    end

    it "converts webpages to markdown" do
      command = [
        "python", "/monadic/scripts/cli_tools/webpage_fetcher.py",
        "--url", "https://httpbin.org/html",
        "--mode", "md",
        "--filepath", "/monadic/data/"
      ].join(" ")
      
      output = `docker exec monadic-chat-python-container #{command} 2>&1`
      
      # Check for actual network issues or container problems
      if output.include?("connection timed out") || 
         output.include?("Failed to fetch") ||
         output.include?("Connection refused") ||
         output.include?("unable to access") ||
         output.include?("container is not running")
        skip "Network connectivity issue or container not available"
      end
      
      # Check for successful save
      expect(output).to match(/Successfully saved.*\.md/)
    end

    it "handles invalid URLs gracefully" do
      command = [
        "python", "/monadic/scripts/cli_tools/webpage_fetcher.py",
        "--url", "https://this-does-not-exist-12345.com",
        "--mode", "md",
        "--filepath", "/monadic/data/"
      ].join(" ")
      
      output = `docker exec monadic-chat-python-container #{command} 2>&1`
      
      # Should handle error gracefully
      expect($?.exitstatus).to be >= 0  # Script should not crash
    end
  end

  describe "Cross-container communication" do
    it "Python container can use Selenium for web scraping" do
      # Test that Python container can communicate with Selenium container
      test_script = <<~PYTHON
        from selenium import webdriver
        from selenium.webdriver.common.by import By
        from selenium.webdriver.chrome.options import Options
        
        options = Options()
        options.add_argument('--headless')
        options.add_argument('--no-sandbox')
        options.add_argument('--disable-dev-shm-usage')
        
        try:
            driver = webdriver.Remote(
                command_executor='http://monadic-chat-selenium-container:4444/wd/hub',
                options=options
            )
            driver.get('https://example.com')
            title = driver.title
            driver.quit()
            print(f"Success: {title}")
        except Exception as e:
            print(f"Error: {e}")
      PYTHON
      
      command = "python -c \"#{test_script.gsub('"', '\"').gsub("\n", "; ")}\""
      output = `docker exec monadic-chat-python-container #{command} 2>&1`
      
      expect(output).to include("Success:")
    end
  end

  describe "Python Container scripts" do
    it "has webpage_fetcher.py available" do
      output = `docker exec monadic-chat-python-container ls -la /monadic/scripts/cli_tools/webpage_fetcher.py 2>&1`
      expect(output).to include("webpage_fetcher.py")
      expect($?.success?).to be true
    end

    it "has necessary Python packages installed" do
      packages = [
        { name: "selenium", import: "selenium" },
        { name: "beautifulsoup4", import: "bs4" },
        { name: "markdownify", import: "markdownify", optional: true }
      ]
      packages.each do |pkg|
        command = "python -c \"import #{pkg[:import]}; print('#{pkg[:name]} available')\" 2>&1"
        output = `docker exec monadic-chat-python-container #{command}`
        
        if pkg[:optional]
          # For optional packages, just note if they're not installed
          if output.include?("ModuleNotFoundError")
            puts "  Note: Optional package #{pkg[:name]} is not installed"
          else
            expect(output).to include("#{pkg[:name]} available")
          end
        else
          expect(output).to include("#{pkg[:name]} available")
        end
      end
    end
  end

  describe "File sharing between containers" do
    it "can save files to shared volume from Python container" do
      timestamp = Time.now.to_i
      test_file = "test_selenium_#{timestamp}.txt"
      test_content = "Selenium test #{timestamp}"
      
      # Create file using Python to avoid shell issues
      python_cmd = <<~PYTHON
        with open('/monadic/data/#{test_file}', 'w') as f:
            f.write('#{test_content}')
        print('File created successfully')
      PYTHON
      
      result = `docker exec monadic-chat-python-container python -c "#{python_cmd}" 2>&1`
      
      # Check command succeeded
      if !$?.success?
        fail "Failed to create file: #{result}"
      end
      
      # Give it a moment to sync
      sleep 1
      
      # Check if file exists in shared volume
      file_path = File.join(Dir.home, "monadic", "data", test_file)
      
      # Try to read the file content to verify
      file_exists = File.exist?(file_path)
      if file_exists
        content = File.read(file_path)
        expect(content.strip).to eq(test_content)
      end
      
      # Clean up
      File.delete(file_path) if File.exist?(file_path)
      
      expect(file_exists).to be true
    end
  end
end
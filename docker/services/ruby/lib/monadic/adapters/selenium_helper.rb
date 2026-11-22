require 'shellwords'
require_relative '../shared_tools/browser_owner'

module MonadicHelper
  def fetch_web_content(url: "")
    puts "DEBUG: fetch_web_content called with url: #{url}" if ENV['APP_DEBUG']
    selenium_fetch(url: url)
  end

  # Fetches a page as Markdown. The fetcher prints it (no file is made in
  # the shared folder).
  def selenium_fetch(url: "")
    command = Shellwords.join(["webpage_fetcher.py", "--url", url.to_s, "--mode", "md", "--output", "stdout"])

    result = nil
    # The fetcher opens a browser session of its own: it takes a slot.
    begin
      MonadicSharedTools::BrowserOwner.with_job do
        send_command(command: command, container: "python") do |stdout, stderr, status|
          page = stdout.to_s.dup.force_encoding("UTF-8").scrub.strip
          result = if !status.success?
                     "Error occurred: #{stderr}"
                   elsif page.empty?
                     "Error occurred: The page could not be read."
                   else
                     page
                   end
        end
      end
    rescue MonadicSharedTools::BrowserOwner::Refused => e
      result = "Error occurred: #{e.message}"
    end

    result
  end
end

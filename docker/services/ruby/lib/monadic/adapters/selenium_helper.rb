require 'shellwords'
require_relative '../utils/environment'
require_relative '../utils/shared_path_guard'

module MonadicHelper
  def fetch_web_content(url: "")
    puts "DEBUG: fetch_web_content called with url: #{url}" if ENV['APP_DEBUG']
    selenium_fetch(url: url)
  end

  def selenium_fetch(url: "")
    max_retrials = 10
    command = Shellwords.join(["webpage_fetcher.py", "--url", url.to_s, "--filepath", "/monadic/data/", "--mode", "md"])

    result = nil 

    send_command(command: command, container: "python") do |stdout, stderr, status|
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]

        shared_volume = Monadic::Utils::Environment.shared_volume

        filepath = File.join(shared_volume, File.basename(filename))

        success = false
        max_retrials.times do
          # The page is a plain file of the shared folder, read never through a link.
          if Monadic::Utils::SharedPathGuard.file_stat(filepath)
            success = true
            break
          elsif max_retrials.positive?
            max_retrials -= 1
            sleep 2
          else
            break
          end
        end

        result = begin
                   raise Errno::ENOENT unless success

                   Monadic::Utils::SharedPathGuard.read_bytes!(filepath).force_encoding("UTF-8")
                 rescue Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError
                   "Error occurred: The #{filename} could not be read."
                 end
      else
        result = "Error occurred: #{stderr}"
      end
    end

    result
  end
end

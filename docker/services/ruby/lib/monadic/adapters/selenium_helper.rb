require_relative '../utils/environment'

module MonadicHelper
  def fetch_web_content(url: "")
    puts "DEBUG: fetch_web_content called with url: #{url}" if ENV['APP_DEBUG']
    selenium_fetch(url: url)
  end

  def selenium_fetch(url: "")
    max_retrials = 10
    command = "webpage_fetcher.py --url \"#{url}\" --filepath \"/monadic/data/\" --mode \"md\""

    result = nil 

    send_command(command: command, container: "python") do |stdout, stderr, status|
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]

        shared_volume = Monadic::Utils::Environment.shared_volume

        filepath = File.join(shared_volume, File.basename(filename))

        success = false
        max_retrials.times do
          if File.exist?(filepath)
            success = true
            break
          elsif max_retrials.positive?
            max_retrials -= 1
            sleep 2
          else
            break
          end
        end

        result = if success
                   File.read(filepath)
                 else
                   "Error occurred: The #{filename} could not be read."
                 end
      else
        result = "Error occurred: #{stderr}"
      end
    end

    result
  end
end

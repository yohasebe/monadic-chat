module MonadicHelper
  def fetch_web_content(url: "")
    selenium_job(url: url)
  end

  def selenium_job(url: "")
    max_retrials = 10
    command = "bash -c '/monadic/scripts/webpage_fetcher.py --url \"#{url}\" --filepath \"/monadic/data/\" --mode \"md\" '"
    # we wait for the following command to finish before returning the output
    send_command(command: command, container: "python") do |stdout, stderr, status|
      if status.success?
        filename = stdout.match(/saved to: (.+\.md)/).to_a[1]

        shared_volume = if IN_CONTAINER
                          MonadicApp::SHARED_VOL
                        else
                          MonadicApp::LOCAL_SHARED_VOL
                        end

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

        if success
          File.read(filepath)
        else
          "Error occurred: The #{filename} could not be read."
        end
      else
        "Error occurred: #{stderr}"
      end
    end
  end
end

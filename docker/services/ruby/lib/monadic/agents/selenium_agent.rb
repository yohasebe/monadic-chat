module MonadicAgent
  def selenium_job(url: "")
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

        filename = File.join(shared_volume, File.basename(filename))

        retrials = 3
        sleep 4
        begin
          contents = File.read(filename)
        rescue StandardError
          if retrials.positive?
            retrials -= 1
            sleep 4
            retry
          else
            "Error occurred: The #{filename} could not be read."
          end
        end
        contents
      else
        "Error occurred: #{stderr}"
      end
    end
  end
end

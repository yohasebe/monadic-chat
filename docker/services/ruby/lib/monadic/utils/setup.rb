module Paths
  max_retries = 5
  retry_delay = 1

  retries = 0

  if IN_CONTAINER
    ENV_PATH = "/monadic/data/.env"
    scripts_path = "/monadic/data/scripts"
    apps_path = "/monadic/data/apps"
  else
    ENV_PATH = File.join(Dir.home, "monadic", "data", ".env")
    scripts_path = File.join(Dir.home, "monadic", "data", "scripts")
    apps_path = File.join(Dir.home, "monadic", "data", "apps")
  end

  unless File.exist?(File.dirname(ENV_PATH))
    FileUtils.mkdir_p(File.dirname(ENV_PATH))

    loop do
      if !File.exist?(File.dirname(ENV_PATH)) && retries <= max_retries
        raise "ERROR: Could not create directory #{File.dirname(ENV_PATH)}"
      end

      if File.exist?(File.dirname(ENV_PATH))
        FileUtils.touch(ENV_PATH) unless File.exist?(ENV_PATH)
        break
      end
      sleep retry_delay
      retries -= 1
    end
  end

  FileUtils.mkdir_p(scripts_path) unless File.exist?(scripts_path) || File.symlink?(scripts_path)
  FileUtils.mkdir_p(apps_path) unless File.exist?(apps_path) || File.symlink?(apps_path)
end

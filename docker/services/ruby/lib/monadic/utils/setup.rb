module Paths
  max_retries = 5
  retry_delay = 1

  retries = 0

  if IN_CONTAINER
    ENV_PATH = "/monadic/data/.env"
    SCRIPTS_PATH = "/monadic/data/scripts"
    APPS_PATH = "/monadic/data/apps"
    VENDORS_PATH = "/monadic/data/vendors"
  else
    ENV_PATH = File.join(Dir.home, "monadic", "data", ".env")
    SCRIPTS_PATH = File.join(Dir.home, "monadic", "data", "scripts")
    APPS_PATH = File.join(Dir.home, "monadic", "data", "apps")
    VENDORS_PATH = File.join(Dir.home, "monadic", "data", "vendors")
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

  FileUtils.mkdir_p(SCRIPTS_PATH) unless File.exist?(SCRIPTS_PATH) || File.symlink?(SCRIPTS_PATH)
  FileUtils.mkdir_p(APPS_PATH) unless File.exist?(APPS_PATH) || File.symlink?(APPS_PATH)
  FileUtils.mkdir_p(VENDORS_PATH) unless File.exist?(VENDORS_PATH) || File.symlink?(VENDORS_PATH)
end

module Paths
  max_retries = 5
  retry_delay = 1

  retries = 0

  if IN_CONTAINER
    ENV_PATH = "/monadic/config/env"
    SCRIPTS_PATH = "/monadic/data/scripts"
    APPS_PATH = "/monadic/data/apps"
    HELPERS_PATH = "/monadic/data/helpers"
    PLUGINS_PATH = "/monadic/data/plugins"
  else
    ENV_PATH = File.join(Dir.home, "monadic", "config", "env")
    SCRIPTS_PATH = File.join(Dir.home, "monadic", "data", "scripts")
    APPS_PATH = File.join(Dir.home, "monadic", "data", "apps")
    HELPERS_PATH = File.join(Dir.home, "monadic", "data", "helpers")
    PLUGINS_PATH = File.join(Dir.home, "monadic", "data", "plugins")
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
  FileUtils.mkdir_p(HELPERS_PATH) unless File.exist?(HELPERS_PATH) || File.symlink?(HELPERS_PATH)
  FileUtils.mkdir_p(PLUGINS_PATH) unless File.exist?(PLUGINS_PATH) || File.symlink?(PLUGINS_PATH)
end

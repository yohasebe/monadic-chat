require 'fileutils'

module Paths
  max_retries = 5
  retry_delay = 1

  retries = 0

  # Resolve the canonical paths once via Environment so the in_container
  # vs dev-mode branch is owned by a single helper (data_path /
  # scripts_path / apps_path / helpers_path / env_path).
  ENV_PATH = Monadic::Utils::Environment.env_path
  SCRIPTS_PATH = Monadic::Utils::Environment.scripts_path
  APPS_PATH = Monadic::Utils::Environment.apps_path
  HELPERS_PATH = Monadic::Utils::Environment.helpers_path

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
end

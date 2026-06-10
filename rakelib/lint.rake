# frozen_string_literal: true

namespace :lint do
  desc "Check docs/translations for deprecated model names"
  task :deprecated_models do
    Dir.chdir(PROJECT_ROOT) do
      system('npm run lint:deprecated-models') || abort('Deprecated model lint failed')
    end
  end

  desc "Check model lifecycle consistency across codebase"
  task :model_consistency do
    Dir.chdir(PROJECT_ROOT) do
      system('npm run lint:model-consistency') || abort('Model consistency check failed')
    end
  end

  # Anti-pattern lint rules (see docs_dev/architecture_hardening_plan.md).
  # Each rule fails the build when its baseline is exceeded; the suite is
  # intentionally split so a partial green/red is still actionable.

  desc "Check that no personal home-directory paths leak into source"
  task :personal_paths do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/check_personal_paths.rb') ||
        abort('Personal path lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc "Check that shell-form interpolations escape user-controlled values"
  task :shell_escape do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/check_shell_escape.rb') ||
        abort('Shell escape lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc "Check that fetch() calls to xhr-dependent routes set X-Requested-With"
  task :xhr_pair do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/check_xhr_pair.rb') ||
        abort('XHR pair lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc 'Check that "/monadic/data" string literals stay inside the Environment helper'
  task :data_path_literals do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/check_data_path_literals.rb') ||
        abort('Data path literal lint failed (see docs_dev/architecture_hardening_plan.md §3.1)')
    end
  end

  desc 'Check that bare ws.send(...) callsites stay inside the monadic-ws.js helper'
  task :bare_ws_send do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/check_bare_ws_send.rb') ||
        abort('Bare ws.send lint failed (see docs_dev/safe_ws_send_plan.md §3)')
    end
  end

  desc "Verify each anti-pattern lint still detects its target via temp fixture"
  task :self_check do
    Dir.chdir(PROJECT_ROOT) do
      system('ruby scripts/lint/spec/check_self_test.rb') ||
        abort('Lint self-check failed: at least one rule no longer detects its target. See scripts/lint/spec/check_self_test.rb')
    end
  end

  desc "Run every anti-pattern lint rule plus the self-check meta-test"
  task :anti_patterns => [:personal_paths, :shell_escape, :xhr_pair, :data_path_literals, :bare_ws_send, :self_check]
end

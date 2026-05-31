# frozen_string_literal: true

# The Privacy Filter is implemented as a Substitution::Provider:
#   Monadic::Substitution::Providers::PrivacyFilter
#
# This file is retained as a backward-compatible alias. Many call sites and
# specs construct or reference `Monadic::Utils::Privacy::Pipeline` directly
# (vendor adapters via privacy_pipeline_for, the agents, library helpers, and
# language_detector.rb which reads Pipeline::PRESIDIO_LANGS). Keeping the alias
# here lets all of them keep working unchanged while the implementation lives
# under the substitution provider tree.
require_relative '../../substitution/providers/privacy_filter'

module Monadic
  module Utils
    module Privacy
      Pipeline = Monadic::Substitution::Providers::PrivacyFilter
    end
  end
end

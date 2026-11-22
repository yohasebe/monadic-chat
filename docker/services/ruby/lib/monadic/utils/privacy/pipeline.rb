# frozen_string_literal: true

# The Privacy Filter is implemented as a Substitution::Provider:
#   Monadic::Substitution::Providers::PrivacyFilter
#
# This file keeps the name `Monadic::Utils::Privacy::Pipeline` for the MCP
# server's masking and for language_detector.rb (Pipeline::PRESIDIO_LANGS),
# while the implementation lives under the substitution provider tree.
require_relative '../../substitution/providers/privacy_filter'

module Monadic
  module Utils
    module Privacy
      Pipeline = Monadic::Substitution::Providers::PrivacyFilter
    end
  end
end

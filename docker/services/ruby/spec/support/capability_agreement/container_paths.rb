# frozen_string_literal: true

# Loaded with -r into every Ruby process of the capability agreement check,
# after no_network.rb. When a process runs as if in the container
# (IN_CONTAINER=true), the container's own paths (/monadic/...) and the file
# the desktop app delivers resolved 1Password references into point under
# MONADIC_TEST_CONTAINER_ROOT instead. Only where those files are changes;
# how they are read does not.
lib = File.expand_path("../../../lib/monadic/utils", __dir__)
require File.join(lib, "environment")
require File.join(lib, "secret_references")

module CapabilityAgreementContainerPaths
  ROOT = ENV.fetch("MONADIC_TEST_CONTAINER_ROOT")

  module Paths
    def resolve_path(container_path, local_path = nil)
      return super unless in_container?

      container_path.sub(%r{\A/monadic(?=/|\z)}, File.join(ROOT, "monadic"))
    end
  end

  module Delivered
    def read_delivered(path = nil)
      path ||= if Monadic::Utils::Environment.in_container?
                 File.join(ROOT, Monadic::Utils::SecretReferences::DELIVERED_PATH)
               else
                 Monadic::Utils::SecretReferences::DELIVERED_PATH
               end
      super(path)
    end
  end
end

Monadic::Utils::Environment.singleton_class.prepend(CapabilityAgreementContainerPaths::Paths)
Monadic::Utils::SecretReferences.singleton_class.prepend(CapabilityAgreementContainerPaths::Delivered)

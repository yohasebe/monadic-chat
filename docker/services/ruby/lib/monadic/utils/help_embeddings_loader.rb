# frozen_string_literal: true

# Compatibility require for callers of the former boot loader. Loading Help
# only defines the on-demand service; installation requires an explicit POST.
require_relative '../help'

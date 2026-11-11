# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      module Outbound
        # A request that was not sent, because what it carries could not be
        # hidden as the chat asks.
        class Refused < StandardError; end
      end
    end
  end
end

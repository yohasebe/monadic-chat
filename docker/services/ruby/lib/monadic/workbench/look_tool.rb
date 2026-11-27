# frozen_string_literal: true

module Monadic
  module Workbench
    # The words of look_at_workbench that its definitions share (typed
    # replies and live voice), in one place.
    module LookTool
      # The item parameter.
      ITEM_PARAM = "An item's id from the work screen observation (its items and changes): look at that item, " \
                   'selected or not. Default: the one the user has selected. An item the user has not selected is ' \
                   "read whole (a whiteboard's shapes and texts, without its picture); the browser only when selected. " \
                   'A put-away item is not read: bring it into Now first (show_on_workbench with its item).'
      # What the description adds about the observation's changes.
      CHANGES_HINT = "When the observation's changes say the user placed or drew on an item and your answer depends " \
                     'on what it shows, look at it first (item: its id); never guess what it shows.'
    end
  end
end

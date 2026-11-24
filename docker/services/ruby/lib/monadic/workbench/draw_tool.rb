# frozen_string_literal: true

module Monadic
  module Workbench
    # How draw_on_whiteboard is described to a model, the same in a chat and
    # in a live conversation (Workbench::Draw does it).
    module DrawTool
      NAME = 'draw_on_whiteboard'
      DESCRIPTION =
        'Draw on a whiteboard in the work screen beside the chat: on the one the user\'s tab shows, or on a new one ' \
        '(new_whiteboard, or when the tab shows none). The board is 1600 wide and 1000 high; x goes right and y down ' \
        'from its top left. shapes is a JSON array of shapes, each with a type: ' \
        '"box" (a rectangle) or "ellipse" with x, y, w, h and an optional text written in its middle (\n starts a new ' \
        'line), size (20, 32, 48 or 72) and fill ("none", "light" or "solid"); ' \
        '"arrow" or "line" with from and to, the ids of the two shapes it joins (its ends are drawn at their edges, ' \
        'and follow them when they move), or with x1, y1, x2, y2; ' \
        '"text" with x, y (its top left), text and size; "pen" with points, a list of [x, y]. ' \
        'Any shape may have an id (letters, digits, - and _: give ids to shapes you join or change later), a color ' \
        '(black, red, orange, yellow, lime, green, sky, blue, violet, pink, white, silver, gray, brown, peach, olive, ' \
        'teal, navy, purple or magenta; violet when left out) and a stroke (3, 6, 12 or 24). ' \
        'A shape with the id of one on the board changes it: give only what changes (x and y to move it). remove ' \
        'takes shapes off by their ids. Look at the whiteboard first (look_at_workbench) to see what is on it, with ' \
        'the ids of its shapes. Leave room between shapes: a box of about 220 × 90 holds a few words of size 20. ' \
        'Use it to explain with a diagram, or when the user asks you to draw. Deleting your message takes off the ' \
        'shapes it added; what the user drew stays.'
      SHAPES = 'A JSON array of the shapes to add or change'
      REMOVE = 'The ids of shapes to take off the whiteboard'
      NEW_BOARD = 'true to draw on a new whiteboard instead of the one the tab shows'
    end
  end
end

# frozen_string_literal: true

require_relative 'whiteboard'

module Monadic
  module Workbench
    # Where the shapes the AI draws go on a whiteboard (Workbench::Draw).
    # A box grows to hold its text; a new shape that partly covers another
    # moves to the nearest free place; boxes given to be laid out are placed
    # in columns (or rows) by the arrows between them, in a free part of the
    # board; and what could not be set right is told (an overlap left, an
    # arrow through a box, a layout too large). One shape inside another is
    # not an overlap: a box in a frame, a text on a box, are meant.
    #
    # Sizes are on the board (Whiteboard::WIDTH × HEIGHT); a text's size is
    # estimated from its characters (wide ones as wide as the text is tall,
    # others about 0.6 of it).
    module WhiteboardLayout
      WIDTH = Whiteboard::WIDTH
      HEIGHT = Whiteboard::HEIGHT
      LINE = 1.25
      NARROW = 0.6
      WIDE = /[\p{Han}\p{Hiragana}\p{Katakana}\p{Hangul}　-〿＀-￯]/
      # Room around a box's text; an ellipse needs about √2 more.
      PAD_X = 24
      PAD_Y = 16
      ELLIPSE = 1.42
      # A box given no size.
      BOX_W = 160
      BOX_H = 60
      # Space between boxes of a column, between columns, and from the edges.
      GAP = 40
      RANK_GAP = 100
      MARGIN = 40
      # How a free place is looked for: in steps of STEP, up to REACH away.
      STEP = 20
      REACH = 600
      BOXES = %w[rect ellipse].freeze
      SOLID = %w[rect ellipse text pen marker].freeze
      LINES = %w[line arrow].freeze
      DIRECTIONS = %w[right down].freeze
      # A right-angled line keeps this far from a box to turn beside it, and
      # goes round others this far from them.
      ROUTE_MIN = 20
      LANE = 30

      module_function

      # [width, height] a text takes at size.
      def text_size(text, size)
        size = size.to_f
        lines = text.to_s.split("\n", -1)
        lines = [''] if lines.empty?
        width = lines.map { |line| line.each_char.sum { |c| c.match?(WIDE) ? size : size * NARROW } }.max
        [width, lines.size * size * LINE]
      end

      # The box a shape takes: [x, y, w, h].
      def bounds(shape)
        case shape['type']
        when 'text'
          w, h = text_size(shape['text'], shape['size'] || Whiteboard::SIZES[0])
          [shape['x'], shape['y'], w, h]
        when 'pen', 'marker' then box_of(shape['points'].map(&:first), shape['points'].map(&:last))
        when 'line', 'arrow' then box_of([shape['x1'], shape['x2']], [shape['y1'], shape['y2']])
        else [shape['x'], shape['y'], shape['w'], shape['h']]
        end
      end

      def box_of(xs, ys)
        [xs.min, ys.min, xs.max - xs.min, ys.max - ys.min]
      end

      # The size a box needs for its text ([w, h]), at least its own.
      def needed(shape)
        return [shape['w'] || BOX_W, shape['h'] || BOX_H] unless shape['text']

        w, h = text_size(shape['text'], shape['size'] || Whiteboard::SIZES[0])
        w += PAD_X * 2
        h += PAD_Y * 2
        if shape['type'] == 'ellipse'
          w *= ELLIPSE
          h *= ELLIPSE
        end
        [[shape['w'] || 0, w.ceil].max, [shape['h'] || 0, h.ceil].max]
      end

      # Grows a box (about its middle, kept on the board) to hold its text.
      # True when it grew.
      def fit!(shape)
        return false unless BOXES.include?(shape['type']) && shape['text']

        w, h = needed(shape)
        w = [w, WIDTH].min
        h = [h, HEIGHT].min
        return false if w <= shape['w'] && h <= shape['h']

        shape['x'] = within(shape['x'] - ((w - shape['w']) / 2.0), 0, WIDTH - w).round(1)
        shape['y'] = within(shape['y'] - ((h - shape['h']) / 2.0), 0, HEIGHT - h).round(1)
        shape['w'] = w.to_f
        shape['h'] = h.to_f
        true
      end

      # Whether two boxes partly cover each other (one inside the other is
      # not), by more than a hair.
      def overlap?(a, b)
        x = [a[0] + a[2], b[0] + b[2]].min - [a[0], b[0]].max
        y = [a[1] + a[3], b[1] + b[3]].min - [a[1], b[1]].max
        x > 2 && y > 2 && !inside?(a, b) && !inside?(b, a)
      end

      def inside?(outer, inner)
        inner[0] >= outer[0] && inner[1] >= outer[1] &&
          inner[0] + inner[2] <= outer[0] + outer[2] && inner[1] + inner[3] <= outer[1] + outer[3]
      end

      # The shapes of others shape partly covers, by id.
      def overlaps(shape, others)
        box = bounds(shape)
        others.select { |o| SOLID.include?(o['type']) && overlap?(box, bounds(o)) }.map { |o| o['id'] }
      end

      # Moves shape to the nearest place within REACH where it covers none of
      # others in part and stays on the board. [dx, dy] moved, or nil.
      def nudge!(shape, others)
        box = bounds(shape)
        solid = others.select { |o| SOLID.include?(o['type']) }.map { |o| bounds(o) }
        return nil if solid.none? { |o| overlap?(box, o) }

        (STEP..REACH).step(STEP) do |r|
          ring(r).each do |dx, dy|
            at = [box[0] + dx, box[1] + dy, box[2], box[3]]
            next unless at[0] >= 0 && at[1] >= 0 && at[0] + at[2] <= WIDTH && at[1] + at[3] <= HEIGHT
            next if solid.any? { |o| overlap?(at, o) }

            move!(shape, dx, dy)
            return [dx, dy]
          end
        end
        nil
      end

      # The steps on the square ring r away, nearest first.
      def ring(r)
        steps = (-r..r).step(STEP).to_a
        (steps.product([-r, r]) + [-r, r].product(steps)).uniq.sort_by { |dx, dy| Math.hypot(dx, dy) }
      end

      def move!(shape, dx, dy)
        case shape['type']
        when 'pen', 'marker' then shape['points'] = shape['points'].map { |x, y| [(x + dx).round(1), (y + dy).round(1)] }
        when 'line', 'arrow'
          %w[x1 x2].each { |k| shape[k] = (shape[k] + dx).round(1) }
          %w[y1 y2].each { |k| shape[k] = (shape[k] + dy).round(1) }
        else
          shape['x'] = (shape['x'] + dx).round(1)
          shape['y'] = (shape['y'] + dy).round(1)
        end
      end

      # The boxes (and texts) a line or an arrow goes through, but those it
      # joins, by id: along its right-angled route when it has one (route
      # 'elbow' between the shapes it joins), else its straight line.
      def crossings(line, others)
        ends = [line['from'], line['to'], line['id']]
        boxes = others.select { |o| %w[rect ellipse text].include?(o['type']) && !ends.include?(o['id']) }
        points = path_of(line, others)
        boxes.select do |o|
          x, y, w, h = bounds(o)
          points.each_cons(2).any? { |a, b| through?(a, b, [x + 4, y + 4, w - 8, h - 8]) }
        end.map { |o| o['id'] }
      end

      # The points a line goes through: its right-angled route between the
      # shapes it joins, or between its ends; else its two ends.
      def path_of(line, shapes)
        a = [line['x1'], line['y1']]
        b = [line['x2'], line['y2']]
        return [a, b] unless line['route'] == 'elbow'

        from = shapes.find { |s| s['id'] == line['from'] }
        to = shapes.find { |s| s['id'] == line['to'] }
        return elbow(a, b) unless from && to

        obstacles = shapes.reject { |s| [from['id'], to['id'], line['id']].include?(s['id']) || LINES.include?(s['type']) }
        route(bounds(from), bounds(to), obstacles.map { |o| bounds(o) })
      end

      # A right-angled way from a to b (points), turning half way along x.
      def elbow(a, b)
        return [a, b] if a[0] == b[0] || a[1] == b[1]

        mx = ((a[0] + b[0]) / 2.0).round(1)
        [a, [mx, a[1]], [mx, b[1]], b]
      end

      # The right-angled route from box a to box b ([x, y, w, h]) that goes
      # through none of obstacles: out of the side facing b and into the side
      # facing a (sideways first, then up or down), else round below them,
      # else round above them; the first when every one goes through one.
      # The page draws joined lines by the same rule.
      def route(a, b, obstacles)
        candidates = side_routes(a, b) + round_routes(a, b, obstacles)
        clear = candidates.find do |points|
          points.each_cons(2).none? do |p, q|
            obstacles.any? { |o| through?(p, q, [o[0] + 4, o[1] + 4, o[2] - 8, o[3] - 8]) }
          end
        end
        (clear || candidates.first).map { |x, y| [x.to_f.round(1), y.to_f.round(1)] }
      end

      def side_routes(a, b)
        ac = [a[0] + (a[2] / 2.0), a[1] + (a[3] / 2.0)]
        bc = [b[0] + (b[2] / 2.0), b[1] + (b[3] / 2.0)]
        out = []
        if b[0] >= a[0] + a[2] + ROUTE_MIN
          out << sideways([a[0] + a[2], ac[1]], [b[0], bc[1]])
        elsif b[0] + b[2] <= a[0] - ROUTE_MIN
          out << sideways([a[0], ac[1]], [b[0] + b[2], bc[1]])
        end
        if b[1] >= a[1] + a[3] + ROUTE_MIN
          out << upright([ac[0], a[1] + a[3]], [bc[0], b[1]])
        elsif b[1] + b[3] <= a[1] - ROUTE_MIN
          out << upright([ac[0], a[1]], [bc[0], b[1] + b[3]])
        end
        out.empty? ? [[ac, bc]] : out
      end

      def sideways(s, e)
        return [s, e] if s[1] == e[1]

        mx = (s[0] + e[0]) / 2.0
        [s, [mx, s[1]], [mx, e[1]], e]
      end

      def upright(s, e)
        return [s, e] if s[0] == e[0]

        my = (s[1] + e[1]) / 2.0
        [s, [s[0], my], [e[0], my], e]
      end

      # Round below everything between a and b, then round above it.
      def round_routes(a, b, obstacles)
        ac = a[0] + (a[2] / 2.0)
        bc = b[0] + (b[2] / 2.0)
        low, high = [ac, bc].minmax
        span = [a, b] + obstacles.select { |o| o[0] <= high && o[0] + o[2] >= low }
        below = span.map { |o| o[1] + o[3] }.max + LANE
        above = span.map { |o| o[1] }.min - LANE
        out = []
        out << [[ac, a[1] + a[3]], [ac, below], [bc, below], [bc, b[1] + b[3]]] if below <= HEIGHT
        out << [[ac, a[1]], [ac, above], [bc, above], [bc, b[1]]] if above >= 0
        out
      end

      # Whether the segment a–b passes through the box (Liang–Barsky).
      def through?(a, b, box)
        return false if box[2] <= 0 || box[3] <= 0

        dx = b[0] - a[0]
        dy = b[1] - a[1]
        low = 0.0
        high = 1.0
        [[-dx, a[0] - box[0]], [dx, box[0] + box[2] - a[0]], [-dy, a[1] - box[1]], [dy, box[1] + box[3] - a[1]]].each do |p, q|
          if p.zero?
            return false if q.negative?
          else
            t = q / p.to_f
            p.negative? ? low = [low, t].max : high = [high, t].min
            return false if low > high
          end
        end
        true
      end

      # Places boxes (inputs with an id, sizes fitted to their texts) in
      # columns (direction 'right') or rows ('down'), each one step after
      # the boxes its arrows (edges, [from, to] ids) come from, in a free
      # part of the board beside what is on it (occupied: boxes). Sets x, y,
      # w and h of each; returns an issue when the whole does not fit.
      def layout!(boxes, edges, direction, occupied)
        ids = boxes.map { |b| b['id'] }
        rank = ids.to_h { |id| [id, 0] }
        known = edges.select { |from, to| rank.key?(from) && rank.key?(to) && from != to }
        ids.size.times do
          moved = false
          known.each do |from, to|
            next unless rank[from] + 1 > rank[to] && rank[from] + 1 < ids.size

            rank[to] = rank[from] + 1
            moved = true
          end
          break unless moved
        end
        boxes.each do |b|
          b['w'], b['h'] = needed(b)
        end
        across = direction == 'down' ? %w[x w] : %w[y h]
        along = direction == 'down' ? %w[y h] : %w[x w]
        groups = boxes.group_by { |b| rank[b['id']] }.sort.map(&:last)
        depth = groups.map { |g| g.sum { |b| b[across[1]] } + (GAP * (g.size - 1)) }
        span = groups.map { |g| g.map { |b| b[along[1]] }.max }
        total_along = span.sum + (RANK_GAP * (groups.size - 1))
        total_across = depth.max
        size = direction == 'down' ? [total_across, total_along] : [total_along, total_across]
        origin = free_origin(size, occupied)
        at_along = direction == 'down' ? origin[1] : origin[0]
        groups.each_with_index do |group, i|
          at_across = (direction == 'down' ? origin[0] : origin[1]) + ((total_across - depth[i]) / 2.0)
          group.each do |b|
            b[along[0]] = (at_along + ((span[i] - b[along[1]]) / 2.0)).round(1)
            b[across[0]] = at_across.round(1)
            at_across += b[across[1]] + GAP
          end
          at_along += span[i] + RANK_GAP
        end
        return nil if size[0] <= WIDTH - (MARGIN * 2) && size[1] <= HEIGHT - (MARGIN * 2)

        "the laid-out boxes (#{size[0].round} × #{size[1].round}) are larger than the board; use fewer or smaller boxes"
      end

      # Where a block of size [w, h] goes: the top left when the board is
      # empty, else below what is on it, else beside it, else the top left.
      def free_origin(size, occupied)
        return [MARGIN, MARGIN] if occupied.empty?

        right = occupied.map { |b| b[0] + b[2] }.max
        bottom = occupied.map { |b| b[1] + b[3] }.max
        [[MARGIN, bottom + GAP], [right + GAP, MARGIN]].each do |x, y|
          return [x, y] if x + size[0] <= WIDTH - MARGIN && y + size[1] <= HEIGHT - MARGIN
        end
        [MARGIN, MARGIN]
      end

      def within(value, low, high) = [[value, low].max, [high, low].max].min
    end
  end
end

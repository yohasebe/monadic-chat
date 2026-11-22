# frozen_string_literal: true

module Monadic
  module WorkScreen
    # What a browser shows, as Page.getLayoutMetrics says it: the viewport
    # in CSS pixels and the device pixels per CSS pixel; and the scale that
    # makes a picture of it no larger than a limit. Used for the work
    # screen's still (Stream) and for a look's picture (Snapshot), each with
    # its own limits and its own way to fail.
    module Viewport
      module_function

      # { x:, y:, width:, height:, ratio: }, or nil when any of it is
      # missing or not a finite number (a viewport that is not known).
      def read(metrics)
        css = metrics.is_a?(Hash) ? metrics['cssVisualViewport'] : nil
        return nil unless css.is_a?(Hash)

        x, y, width, height = css.values_at('pageX', 'pageY', 'clientWidth', 'clientHeight')
        return nil unless [x, y, width, height].all? { |v| finite?(v) } && width.positive? && height.positive?
        return nil if x.negative? || y.negative?

        device = metrics.dig('contentSize', 'width')
        page = metrics.dig('cssContentSize', 'width')
        ratio = finite?(device) && finite?(page) && device.positive? && page.positive? ? device.to_f / page : 1.0
        { x: x, y: y, width: width, height: height, ratio: ratio }
      end

      # The scale (at most 1) that keeps the viewport's picture within
      # max_width × max_height device pixels, and within max_pixels when
      # given.
      def scale(view, max_width:, max_height:, max_pixels: nil)
        width = view[:width] * view[:ratio]
        height = view[:height] * view[:ratio]
        limits = [1.0, max_width / width, max_height / height]
        limits << Math.sqrt(max_pixels / (width * height)) if max_pixels
        limits.min
      end

      def finite?(value)
        value.is_a?(Numeric) && value.finite?
      end
    end
  end
end

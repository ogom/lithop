# frozen_string_literal: true

module Lithop
  # Generates a closed axis-aligned box with outward-facing triangles.
  class BoxGeometry
    attr_reader :triangle_count

    def initialize(width:, height:, z_min:, z_max:)
      @width = width
      @height = height
      @z_min = z_min
      @z_max = z_max
      @triangle_count = 12
      raise InputError, "box dimensions must be positive" unless width.positive? && height.positive? && z_max > z_min
    end

    def each_triangle(&block)
      return enum_for(__method__) unless block

      x0 = 0.0
      y0 = 0.0
      x1 = @width
      y1 = @height
      z0 = @z_min
      z1 = @z_max
      quad([x0, y0, z0], [x0, y1, z0], [x1, y1, z0], [x1, y0, z0], &block)
      quad([x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1], &block)
      quad([x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1], &block)
      quad([x1, y0, z0], [x1, y1, z0], [x1, y1, z1], [x1, y0, z1], &block)
      quad([x1, y1, z0], [x0, y1, z0], [x0, y1, z1], [x1, y1, z1], &block)
      quad([x0, y1, z0], [x0, y0, z0], [x0, y0, z1], [x0, y1, z1], &block)
    end

    private

    def quad(a, b, c, d)
      yield [a, b, c]
      yield [a, c, d]
    end
  end
end

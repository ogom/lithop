# frozen_string_literal: true

module Lithop
  # Generates the closed triangle mesh for a monochrome height field.
  # rubocop:disable-next Metrics/ClassLength
  class Geometry
    # rubocop:disable-next Metrics/ParameterLists
    def initialize(
      heights:, columns:, rows:, x_boundaries:, y_boundaries:, optimize_bottom: false, base_height: 0.0
    )
      @heights = heights
      @columns = columns
      @rows = rows
      @x = x_boundaries
      @y = y_boundaries
      @optimize_bottom = optimize_bottom
      @base_height = base_height
      expected = (columns + 1) * (rows + 1)
      raise InputError, "expected #{expected} vertex heights, got #{heights.length}" unless heights.length == expected
      raise InputError, "base height must be finite" unless base_height.is_a?(Numeric) && base_height.finite?
      raise InputError, "vertex heights must not be below the base" if heights.any? { |height| height < base_height }
    end

    def each_triangle(&block)
      return enum_for(__method__) unless block

      @rows.times do |row|
        @columns.times { |column| emit_cell(row, column, &block) }
      end
      emit_perimeter(&block)
      emit_bottom_fan(&block) if @optimize_bottom
    end

    private

    def emit_cell(row, column, &)
      x0 = @x.fetch(column)
      x1 = @x.fetch(column + 1)
      y0 = @y.last - @y.fetch(row + 1)
      y1 = @y.last - @y.fetch(row)
      top_left = [x0, y1, height(row, column)]
      top_right = [x1, y1, height(row, column + 1)]
      bottom_right = [x1, y0, height(row + 1, column + 1)]
      bottom_left = [x0, y0, height(row + 1, column)]

      yield [top_left, bottom_left, bottom_right]
      yield [top_left, bottom_right, top_right]
      return if @optimize_bottom

      quad([x0, y1, @base_height], [x1, y1, @base_height],
           [x1, y0, @base_height], [x0, y0, @base_height], &)
    end

    def emit_perimeter(&)
      @rows.times do |row|
        emit_left_side(row, &)
        emit_right_side(row, &)
      end
      @columns.times do |column|
        emit_bottom_side(column, &)
        emit_top_side(column, &)
      end
    end

    def emit_left_side(row, &)
      y0 = @y.last - @y.fetch(row + 1)
      y1 = @y.last - @y.fetch(row)
      quad(
        [0.0, y0, @base_height], [0.0, y0, height(row + 1, 0)],
        [0.0, y1, height(row, 0)], [0.0, y1, @base_height], &
      )
    end

    def emit_right_side(row, &)
      x = @x.last
      y0 = @y.last - @y.fetch(row + 1)
      y1 = @y.last - @y.fetch(row)
      quad(
        [x, y0, @base_height], [x, y1, @base_height],
        [x, y1, height(row, @columns)], [x, y0, height(row + 1, @columns)], &
      )
    end

    def emit_bottom_side(column, &)
      x0 = @x.fetch(column)
      x1 = @x.fetch(column + 1)
      quad(
        [x0, 0.0, @base_height], [x1, 0.0, @base_height],
        [x1, 0.0, height(@rows, column + 1)], [x0, 0.0, height(@rows, column)], &
      )
    end

    def emit_top_side(column, &)
      x0 = @x.fetch(column)
      x1 = @x.fetch(column + 1)
      y = @y.last
      quad(
        [x0, y, @base_height], [x0, y, height(0, column)],
        [x1, y, height(0, column + 1)], [x1, y, @base_height], &
      )
    end

    def emit_bottom_fan
      center = [@x.last.fdiv(2), @y.last.fdiv(2), @base_height]
      rendered_y = @y.reverse.map { |y| @y.last - y }
      perimeter = rendered_y.map { |y| [0.0, y, @base_height] }
      @x.drop(1).each { |x| perimeter << [x, @y.last, @base_height] }
      rendered_y.reverse.drop(1).each { |y| perimeter << [@x.last, y, @base_height] }
      @x.reverse.drop(1).first(@x.length - 2).each { |x| perimeter << [x, 0.0, @base_height] }
      perimeter.each_with_index do |from, index|
        yield [center, from, perimeter.fetch((index + 1) % perimeter.length)]
      end
    end

    def height(row, column)
      @heights.fetch((row * (@columns + 1)) + column)
    end

    def quad(a, b, c, d)
      yield [a, b, c]
      yield [a, c, d]
    end
  end
end

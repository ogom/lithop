# frozen_string_literal: true

module Lithop
  # Builds one closed pigment solid from a single contiguous Z interval per XY cell.
  # rubocop:disable-next Metrics/ClassLength
  class ColumnGeometry
    include Enumerable

    def initialize(model:, material:)
      unless Palette::PIGMENTS.include?(material)
        raise InputError, "column geometry requires a CMY pigment: #{material.inspect}"
      end

      @model = model
      @material = material
      @intervals = model.cells.map { |cell| interval(cell.materials) }.freeze
      @topology = ColumnTopology.new(model:, intervals: @intervals)
    end

    def each_triangle(&)
      return enum_for(__method__) unless block_given?

      @model.rows.times do |row|
        @model.columns.times do |column|
          current = interval_at(row, column)
          next unless current

          emit_caps(row, column, current, &)
          emit_sides(row, column, current, &)
        end
      end
    end

    def each(&) = each_triangle(&)

    def release_cache! = @topology.release_cache!

    def triangle_count
      @model.rows.times.sum do |row|
        @model.columns.times.sum do |column|
          current = interval_at(row, column)
          next 0 unless current

          side_layers = exposed_layer_count(current, grouped_interval(row, column, row, column - 1)) +
                        exposed_layer_count(current, grouped_interval(row, column, row, column + 1)) +
                        exposed_layer_count(current, grouped_interval(row, column, row + 1, column)) +
                        exposed_layer_count(current, grouped_interval(row, column, row - 1, column))
          4 + (side_layers * 2)
        end
      end
    end

    private

    def interval(materials)
      first = materials.index(@material)
      return unless first

      last = materials.rindex(@material)
      [first, last + 1]
    end

    def interval_at(row, column)
      return if row.negative? || column.negative? || row >= @model.rows || column >= @model.columns

      @intervals.fetch((row * @model.columns) + column)
    end

    def emit_caps(row, column, current, &)
      bottom, top = current
      bottom_owner = [bottom, row, column]
      top_owner = [top - 1, row, column]
      quad(
        vertex(column, row + 1, bottom, bottom_owner), vertex(column, row, bottom, bottom_owner),
        vertex(column + 1, row, bottom, bottom_owner), vertex(column + 1, row + 1, bottom, bottom_owner), &
      )
      quad(
        vertex(column, row + 1, top, top_owner), vertex(column + 1, row + 1, top, top_owner),
        vertex(column + 1, row, top, top_owner), vertex(column, row, top, top_owner), &
      )
    end

    # Four directions intentionally stay together so their winding order is easy to compare.
    # rubocop:disable-next Metrics/AbcSize
    def emit_sides(row, column, current, &)
      emit_side(current, grouped_interval(row, column, row, column - 1)) do |layer|
        owner = [layer, row, column]
        quad(
          vertex(column, row + 1, layer, owner), vertex(column, row + 1, layer + 1, owner),
          vertex(column, row, layer + 1, owner), vertex(column, row, layer, owner), &
        )
      end
      emit_side(current, grouped_interval(row, column, row, column + 1)) do |layer|
        owner = [layer, row, column]
        quad(
          vertex(column + 1, row + 1, layer, owner), vertex(column + 1, row, layer, owner),
          vertex(column + 1, row, layer + 1, owner), vertex(column + 1, row + 1, layer + 1, owner), &
        )
      end
      emit_side(current, grouped_interval(row, column, row + 1, column)) do |layer|
        owner = [layer, row, column]
        quad(
          vertex(column, row + 1, layer, owner), vertex(column + 1, row + 1, layer, owner),
          vertex(column + 1, row + 1, layer + 1, owner), vertex(column, row + 1, layer + 1, owner), &
        )
      end
      emit_side(current, grouped_interval(row, column, row - 1, column)) do |layer|
        owner = [layer, row, column]
        quad(
          vertex(column, row, layer, owner), vertex(column, row, layer + 1, owner),
          vertex(column + 1, row, layer + 1, owner), vertex(column + 1, row, layer, owner), &
        )
      end
    end

    def emit_side(current, neighbour, &)
      bottom, top = current
      unless neighbour
        emit_layers(bottom, top, &)
        return
      end
      neighbour_bottom, neighbour_top = neighbour
      if neighbour_top <= bottom || neighbour_bottom >= top
        emit_layers(bottom, top, &)
        return
      end
      emit_layers(bottom, [top, neighbour_bottom].min, &) if neighbour_bottom > bottom
      return unless neighbour_top < top

      emit_layers([bottom, neighbour_top].max, top, &)
    end

    def exposed_layer_count(current, neighbour)
      bottom, top = current
      return top - bottom unless neighbour

      neighbour_bottom, neighbour_top = neighbour
      overlap = [[top, neighbour_top].min - [bottom, neighbour_bottom].max, 0].max
      (top - bottom) - overlap
    end

    def grouped_interval(row, column, neighbour_row, neighbour_column)
      return unless @topology.same_group?(row, column, neighbour_row, neighbour_column)

      interval_at(neighbour_row, neighbour_column)
    end

    def emit_layers(bottom, top, &)
      (bottom...top).each(&)
    end

    def vertex(x_index, row_boundary, z_index, owner)
      @topology.vertex(x_index, row_boundary, z_index, owner)
    end

    def quad(a, b, c, d)
      yield [a, b, c]
      yield [a, c, d]
    end
  end
end

# frozen_string_literal: true

module Lithop
  # Generates the exposed triangles for one material in a voxel model.
  class VoxelGeometry
    Vertex = VoxelTopology::Vertex

    def initialize(model:, material:)
      raise InputError, "unknown material: #{material.inspect}" unless Palette::MATERIALS.include?(material)

      @model = model
      @material = material
      @topology = VoxelTopology.new(model:, material:)
    end

    def each_triangle(&)
      return enum_for(__method__) unless block_given?

      (@model.z_boundaries.length - 1).times do |layer|
        @model.rows.times do |row|
          @model.columns.times do |column|
            emit_voxel(layer, row, column, &) if occupied?(layer, row, column)
          end
        end
      end
    end

    def triangle_count
      count = 0
      each_occupied_voxel do |layer, row, column|
        count += 2 unless occupied?(layer - 1, row, column)
        count += 2 unless occupied?(layer + 1, row, column)
        count += 2 unless occupied?(layer, row, column - 1)
        count += 2 unless occupied?(layer, row, column + 1)
        count += 2 unless occupied?(layer, row + 1, column)
        count += 2 unless occupied?(layer, row - 1, column)
      end
      count
    end

    private

    def each_occupied_voxel
      (@model.z_boundaries.length - 1).times do |layer|
        @model.rows.times do |row|
          @model.columns.times do |column|
            yield layer, row, column if occupied?(layer, row, column)
          end
        end
      end
    end

    def emit_voxel(layer, row, column, &)
      owner = [layer, row, column]
      x0 = column
      x1 = column + 1
      y0 = row + 1
      y1 = row
      z0 = layer
      z1 = layer + 1

      emit_bottom(x0, x1, y0, y1, z0, owner, &) unless occupied?(layer - 1, row, column)
      emit_top(x0, x1, y0, y1, z1, owner, &) unless occupied?(layer + 1, row, column)
      emit_left(x0, y0, y1, z0, z1, owner, &) unless occupied?(layer, row, column - 1)
      emit_right(x1, y0, y1, z0, z1, owner, &) unless occupied?(layer, row, column + 1)
      emit_front(x0, x1, y0, z0, z1, owner, &) unless occupied?(layer, row + 1, column)
      emit_back(x0, x1, y1, z0, z1, owner, &) unless occupied?(layer, row - 1, column)
    end

    def occupied?(layer, row, column)
      @model.material_at(layer, row, column) == @material
    end

    def emit_bottom(x0, x1, y0, y1, z, owner, &)
      quad(vertex(x0, y0, z, owner), vertex(x0, y1, z, owner),
           vertex(x1, y1, z, owner), vertex(x1, y0, z, owner), &)
    end

    def emit_top(x0, x1, y0, y1, z, owner, &)
      quad(vertex(x0, y0, z, owner), vertex(x1, y0, z, owner),
           vertex(x1, y1, z, owner), vertex(x0, y1, z, owner), &)
    end

    def emit_left(x, y0, y1, z0, z1, owner, &)
      quad(vertex(x, y0, z0, owner), vertex(x, y0, z1, owner),
           vertex(x, y1, z1, owner), vertex(x, y1, z0, owner), &)
    end

    def emit_right(x, y0, y1, z0, z1, owner, &)
      quad(vertex(x, y0, z0, owner), vertex(x, y1, z0, owner),
           vertex(x, y1, z1, owner), vertex(x, y0, z1, owner), &)
    end

    def emit_front(x0, x1, y, z0, z1, owner, &)
      quad(vertex(x0, y, z0, owner), vertex(x1, y, z0, owner),
           vertex(x1, y, z1, owner), vertex(x0, y, z1, owner), &)
    end

    def emit_back(x0, x1, y, z0, z1, owner, &)
      quad(vertex(x0, y, z0, owner), vertex(x0, y, z1, owner),
           vertex(x1, y, z1, owner), vertex(x1, y, z0, owner), &)
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

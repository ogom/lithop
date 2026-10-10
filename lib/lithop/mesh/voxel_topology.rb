# frozen_string_literal: true

module Lithop
  # Assigns stable topological identities to multipart voxel vertices.
  class VoxelTopology
    Vertex = Data.define(:x, :y, :z, :topology) do
      def coordinates
        [x, y, z]
      end

      def hash = topology.hash

      def eql?(other) = other.is_a?(self.class) && topology.eql?(other.topology)

      alias_method :==, :eql?
    end

    def initialize(model:, material:)
      @model = model
      @material = material
      @component_cache = {}
    end

    def vertex(x_index, row_boundary, z_index, owner)
      Vertex.new(
        x: @model.x_boundaries.fetch(x_index),
        y: @model.y_boundaries.last - @model.y_boundaries.fetch(row_boundary),
        z: @model.z_boundaries.fetch(z_index),
        topology: topology_key(x_index, row_boundary, z_index, owner)
      )
    end

    private

    def topology_key(x_index, row_boundary, z_index, owner)
      cache_key = [x_index, row_boundary, z_index]
      components = @component_cache[cache_key] ||= components_at(x_index, row_boundary, z_index)
      [x_index, row_boundary, z_index, components.fetch(owner)]
    end

    def components_at(x_index, row_boundary, z_index)
      incident = incident_voxels(x_index, row_boundary, z_index)
      components = {}
      incident.each do |owner|
        next if components.key?(owner)

        component = []
        pending = [owner]
        until pending.empty?
          current = pending.pop
          next if component.include?(current)

          component << current
          pending.concat(incident.reject do |candidate|
            component.include?(candidate) || !face_neighbours?(current, candidate)
          end)
        end
        root = component.min
        component.each { |member| components[member] = root }
      end
      components.freeze
    end

    def incident_voxels(x_index, row_boundary, z_index)
      [z_index - 1, z_index].product(
        [row_boundary - 1, row_boundary],
        [x_index - 1, x_index]
      ).select { |layer, row, column| occupied?(layer, row, column) }
    end

    def face_neighbours?(left, right)
      left.zip(right).sum { |a, b| (a - b).abs } == 1
    end

    def occupied?(layer, row, column)
      @model.material_at(layer, row, column) == @material
    end
  end
end

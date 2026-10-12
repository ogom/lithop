# frozen_string_literal: true

module Lithop
  # Validates that triangle meshes are closed and consistently oriented.
  module MeshValidator
    module_function

    def validate!(triangles)
      report!(triangles)
      true
    end

    Report = Data.define(:triangle_count, :edge_count, :component_volumes, :volume)
    Topology = Data.define(:edges, :triangle_volumes, :triangle_count)

    # Vertex-only contacts remain separate components with positive volumes.
    def report!(triangles)
      topology = collect_topology(triangles)
      validate_edges!(topology.edges)
      component_volumes = component_volumes(
        topology.triangle_count,
        neighbours_for(topology.edges),
        topology.triangle_volumes
      )
      raise InputError, "mesh is not outward-facing" if component_volumes.any? { |volume| volume <= 0.0 }

      Report.new(
        triangle_count: topology.triangle_count,
        edge_count: topology.edges.length,
        component_volumes: component_volumes.freeze,
        volume: component_volumes.sum
      )
    end

    def collect_topology(triangles)
      edges = Hash.new { |hash, key| hash[key] = [] }
      triangle_volumes = []
      triangle_count = 0

      triangles.each do |triangle|
        validate_triangle!(triangle)
        triangle_index = triangle_count
        triangle_count += 1
        triangle_volumes << signed_volume(triangle)
        triangle.each_with_index do |from, index|
          to = triangle[(index + 1) % 3]
          key = { from => true, to => true }.freeze
          edges[key] << [triangle_index, from, to]
        end
      end

      raise InputError, "mesh contains no triangles" if triangle_count.zero?

      Topology.new(edges:, triangle_volumes:, triangle_count:)
    end

    def validate_triangle!(triangle)
      raise InputError, "triangle must contain three vertices" unless triangle.length == 3
      raise InputError, "mesh contains a zero-area triangle" if zero_area?(triangle)
    end

    def validate_edges!(edges)
      invalid = edges.find do |_key, faces|
        faces.length != 2 || faces[0].drop(1) != faces[1].drop(1).reverse
      end
      raise InputError, "mesh is not a closed, consistently oriented surface" if invalid
    end

    def neighbours_for(edges)
      edges.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(_key, faces), neighbours|
        left, right = faces.map(&:first)
        neighbours[left] << right
        neighbours[right] << left
      end
    end

    def zero_area?(triangle)
      a, b, c = triangle.map { |vertex| coordinates(vertex) }
      ab = b.zip(a).map { |left, right| left - right }
      ac = c.zip(a).map { |left, right| left - right }
      cross = [
        (ab[1] * ac[2]) - (ab[2] * ac[1]),
        (ab[2] * ac[0]) - (ab[0] * ac[2]),
        (ab[0] * ac[1]) - (ab[1] * ac[0])
      ]
      cross.all?(&:zero?)
    end

    def coordinates(vertex)
      vertex.respond_to?(:coordinates) ? vertex.coordinates : vertex
    end

    def signed_volume(triangle)
      a, b, c = triangle.map { |vertex| coordinates(vertex) }
      (
        (a[0] * ((b[1] * c[2]) - (b[2] * c[1]))) -
        (a[1] * ((b[0] * c[2]) - (b[2] * c[0]))) +
        (a[2] * ((b[0] * c[1]) - (b[1] * c[0])))
      ) / 6.0
    end

    def component_volumes(triangle_count, neighbours, triangle_volumes)
      visited = Array.new(triangle_count, false)
      triangle_count.times.filter_map do |start|
        next if visited[start]

        pending = [start]
        volume = 0.0
        until pending.empty?
          index = pending.pop
          next if visited[index]

          visited[index] = true
          volume += triangle_volumes.fetch(index)
          pending.concat(neighbours.fetch(index, []).reject { |candidate| visited[candidate] })
        end
        volume
      end
    end
    private_class_method :coordinates, :zero_area?, :signed_volume, :component_volumes, :collect_topology,
                         :validate_triangle!, :validate_edges!, :neighbours_for
  end
end

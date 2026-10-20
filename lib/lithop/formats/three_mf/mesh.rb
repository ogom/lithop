# frozen_string_literal: true

module Lithop
  # Indexes vertices and triangles for a 3MF mesh resource.
  class ThreeMFMesh
    NATIVE_BATCH_SIZE = 8_192
    MAXIMUM_NATIVE_TOPOLOGY_KEY = (2**63) - 1
    class UnsupportedNativeTopology < StandardError; end

    attr_reader :vertices, :vertex_indices, :triangle_count, :native_mesh

    def initialize(triangles:)
      @triangles = triangles
      Native.enabled? ? index_native_resources : index_ruby_resources
    end

    def each_indexed_triangle
      return enum_for(__method__) unless block_given?

      @triangles.each do |triangle|
        yield triangle.map { |vertex| vertex_indices.fetch(vertex) }
      end
    end

    def native_indexed? = !native_mesh.nil?

    def vertex_count = native_indexed? ? native_mesh.vertex_count : vertices.length

    def center
      return native_mesh.center if native_indexed?

      axes = vertices.transpose
      axes.map { |values| (values.min + values.max) / 2.0 }
    end

    private

    def index_native_resources
      if @triangles.respond_to?(:native_indexed_mesh)
        @native_mesh = @triangles.native_indexed_mesh
        raise InputError, "3MF mesh contains no triangles" if native_mesh.vertex_count.zero?

        @triangle_count = native_mesh.triangle_count
        @vertices = nil
        @vertex_indices = nil
        return
      end

      @native_mesh = Native::MeshBuilder.new
      coordinates = []
      topology_keys = []
      count = 0
      @triangles.each do |triangle|
        validate_triangle!(triangle)
        triangle.each do |vertex|
          coordinates.concat(coordinates(vertex))
          topology_keys << native_topology_key(vertex)
        end
        count += 1
        flush_native_batch(coordinates, topology_keys) if (count % NATIVE_BATCH_SIZE).zero?
      end
      flush_native_batch(coordinates, topology_keys)
      raise InputError, "3MF mesh contains no triangles" if native_mesh.vertex_count.zero?

      @triangle_count = native_mesh.triangle_count
      @vertices = nil
      @vertex_indices = nil
    rescue UnsupportedNativeTopology
      @native_mesh = nil
      index_ruby_resources
    end

    def flush_native_batch(coordinates, topology_keys)
      return if coordinates.empty?

      native_mesh.add_batch(coordinates, topology_keys)
      coordinates.clear
      topology_keys.clear
    end

    def native_topology_key(vertex)
      return -1 unless vertex.respond_to?(:topology)

      topology = vertex.topology
      unless topology.is_a?(Integer) && topology.between?(0, MAXIMUM_NATIVE_TOPOLOGY_KEY)
        raise UnsupportedNativeTopology
      end

      topology
    end

    def index_ruby_resources
      @vertices = []
      @vertex_indices = {}
      @triangle_count = 0

      @triangles.each do |triangle|
        validate_triangle!(triangle)
        triangle.each { |vertex| index_vertex(vertex) }
        @triangle_count += 1
      end
      raise InputError, "3MF mesh contains no triangles" if vertices.empty?
    end

    def index_vertex(vertex)
      return if vertex_indices.key?(vertex)

      vertex_indices[vertex] = vertices.length
      vertices << coordinates(vertex).freeze
    end

    def validate_triangle!(triangle)
      valid = triangle.is_a?(Array) && triangle.length == 3 && triangle.all? do |vertex|
        point = coordinates(vertex)
        point.length == 3 && point.all? { |value| value.is_a?(Numeric) && value.finite? }
      end
      raise InputError, "3MF triangle must contain three finite XYZ vertices" unless valid
    end

    def coordinates(vertex)
      vertex.respond_to?(:coordinates) ? vertex.coordinates : vertex
    end
  end
end

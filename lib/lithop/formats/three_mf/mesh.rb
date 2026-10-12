# frozen_string_literal: true

module Lithop
  # Indexes vertices and triangles for a 3MF mesh resource.
  class ThreeMFMesh
    attr_reader :vertices, :vertex_indices, :triangle_count

    def initialize(triangles:)
      @triangles = triangles
      index_resources
    end

    def each_indexed_triangle
      return enum_for(__method__) unless block_given?

      @triangles.each do |triangle|
        yield triangle.map { |vertex| vertex_indices.fetch(vertex) }
      end
    end

    private

    def index_resources
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

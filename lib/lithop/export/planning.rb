# frozen_string_literal: true

module Lithop
  # Builds the reference-style overlapping White height field and contiguous CMY columns.
  class ReferenceMaterialMeshPlan
    def initialize(model:, white_geometry:, maximum_triangles:, limit_message:)
      @model = model
      @white_geometry = white_geometry
      @maximum_triangles = maximum_triangles
      @limit_message = limit_message
    end

    def call
      geometries = [[:white, @white_geometry]]
      Palette::PIGMENTS.each do |material|
        geometries << [material, ColumnGeometry.new(model: @model, material:)] if @model.materials.include?(material)
      end
      counts = geometries.to_h do |material, geometry|
        count = geometry.respond_to?(:triangle_count) ? geometry.triangle_count : geometry.each_triangle.count
        [material, count]
      end
      triangle_count = counts.values.sum
      raise ConfigurationError, @limit_message.call(triangle_count) if triangle_count > @maximum_triangles

      MaterialMeshPlan::Result.new(
        parts: geometries.map do |material, geometry|
          triangles = geometry.is_a?(ColumnGeometry) ? geometry : geometry.each_triangle
          ThreeMF::Part.new(material:, triangles:)
        end,
        triangle_count:,
        triangle_counts_by_material: counts.freeze
      )
    end
  end

  # Builds material parts and exact triangle counts before writing a 3MF package.
  class MaterialMeshPlan
    Result = Data.define(:parts, :triangle_count, :triangle_counts_by_material) do
      def validate!(three_mf_result)
        return true if triangle_count == three_mf_result.triangle_count

        raise Error, "planned and written 3MF triangle counts differ"
      end
    end

    def initialize(model:, maximum_triangles:, label:, limit_message: nil)
      @model = model
      @maximum_triangles = maximum_triangles
      @label = label
      @limit_message = limit_message
    end

    def call
      geometries = @model.materials.map do |material|
        geometry = VoxelGeometry.new(model: @model, material:)
        [material, geometry, geometry.triangle_count]
      end
      triangle_count = geometries.sum { |_material, _geometry, count| count }
      raise ConfigurationError, limit_message(triangle_count) if triangle_count > @maximum_triangles

      Result.new(
        parts: geometries.map do |material, geometry, _count|
          ThreeMF::Part.new(material:, triangles: geometry.each_triangle)
        end,
        triangle_count:,
        triangle_counts_by_material: geometries.to_h do |material, _geometry, count|
          [material, count]
        end.freeze
      )
    end

    def limit_message(triangle_count)
      return @limit_message.call(triangle_count) if @limit_message

      "#{@label} has #{triangle_count} triangles; maximum is #{@maximum_triangles}"
    end
  end
end

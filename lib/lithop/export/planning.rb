# frozen_string_literal: true

module Lithop
  # Splits the reference White carrier and CMY pigments into closed Z-region parts.
  class ZSeparatedMaterialMeshPlan
    Entry = Data.define(:material, :geometry, :name, :region, :build_z_offset)

    def initialize(model:, base_geometry:, top_geometry:, settings:, maximum_triangles:, limit_message:)
      @model = model
      @base_geometry = base_geometry
      @top_geometry = top_geometry
      @settings = settings
      @maximum_triangles = maximum_triangles
      @limit_message = limit_message
    end

    def call
      entries = build_entries
      entry_counts = entries.map { |entry| triangle_count(entry.geometry) }
      total = entry_counts.sum
      raise ConfigurationError, @limit_message.call(total) if total > @maximum_triangles

      MaterialMeshPlan::Result.new(
        parts: entries.map do |entry|
          ThreeMF::Part.new(
            material: entry.material, triangles: triangle_source(entry.geometry),
            name: entry.name, region: entry.region, build_z_offset: entry.build_z_offset
          )
        end,
        triangle_count: total,
        triangle_counts_by_material: counts_by_material(entries, entry_counts)
      )
    end

    private

    def build_entries
      entries = []
      color_ranges.each_with_index do |range, index|
        region_model = LayerRegionModel.new(model: @model, layer_range: range)
        region = "color_region_#{index + 1}"
        build_z_offset = @settings.layer_structure.base_white_thickness - region_model.z_boundaries.first
        entries << Entry.new(
          material: :white, geometry: @base_geometry, name: "Color region #{index + 1} Base White",
          region:, build_z_offset: 0.0
        )
        entries << Entry.new(
          material: :white,
          geometry: color_region_white_geometry(region_model),
          name: "Color region #{index + 1} White",
          region:,
          build_z_offset:
        )
        Palette::PIGMENTS.each do |material|
          next unless region_model.materials.include?(material)

          entries << Entry.new(
            material:,
            geometry: ColumnGeometry.new(model: region_model, material:),
            name: "Color region #{index + 1} #{material.to_s.capitalize}",
            region:,
            build_z_offset:
          )
        end
      end
      entries << Entry.new(
        material: :white, geometry: @top_geometry, name: "Top White",
        region: "top_white", build_z_offset: -@settings.layer_structure.color_region_end
      )
      entries
    end

    def color_ranges
      @settings.layer_structure.color_region_layer_ranges(@settings.color_region_parts)
    end

    def color_region_white_geometry(model)
      BoxGeometry.new(
        width: model.x_boundaries.last,
        height: model.y_boundaries.last,
        z_min: model.z_boundaries.first,
        z_max: model.z_boundaries.last
      )
    end

    def triangle_count(geometry)
      geometry.respond_to?(:triangle_count) ? geometry.triangle_count : geometry.each_triangle.count
    end

    def triangle_source(geometry)
      geometry.is_a?(ColumnGeometry) ? geometry : geometry.each_triangle
    end

    def counts_by_material(entries, entry_counts)
      entries.zip(entry_counts).each_with_object(Hash.new(0)) do |(entry, count), totals|
        totals[entry.material] += count
      end.freeze
    end
  end

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

# frozen_string_literal: true

module Lithop
  # Builds the color-model portion of an export manifest.
  # rubocop:disable-next Metrics/ClassLength
  class ExportColorMetadata
    def initialize(settings:, calibration:)
      @settings = settings
      @calibration = calibration
    end

    # rubocop:disable-next Metrics/MethodLength
    def call(artifacts)
      {
        file: artifacts.three_mf_name,
        files: artifacts.three_mf_names,
        format: "3MF",
        property: "3MF color group and Bambu Studio part extruder assignments",
        calibration: @calibration.metadata,
        calibration_profile_id: @calibration.profile&.profile_id,
        id: @settings.color_model,
        color_layer_count: @settings.color_layer_count,
        pigment_order: @settings.pigment_order,
        color_layer_sequence: [*@settings.pigment_order, :white],
        layout_profile: @settings.layout_profile,
        base_white_layers: @settings.base_white_layers,
        minimum_top_white_layers: @settings.minimum_top_white_layers,
        z_part_separation: z_part_separation,
        thickness_mm: thickness_structure,
        physical_material_layers_encoded: true,
        bambu_studio_material_assignments_encoded: true,
        pigments: Palette::PIGMENTS,
        subtractive_mixes: Palette::SUBTRACTIVE_MIXES,
        luminance_control: {
          material: "White",
          method: luminance_method
        },
        preview: {
          method: "nominal_recipe_color_with_relative_thickness",
          colorimetric: false,
          source: "same_material_model_as_3mf",
          calibration_profile_id: @calibration.profile&.profile_id
        },
        material_count: artifacts.three_mf.material_count,
        object_count: artifacts.three_mf.object_count,
        used_materials: material_names(used_materials(artifacts)),
        unused_materials: material_names(Palette::MATERIALS - used_materials(artifacts)),
        triangle_counts_by_material: artifacts.three_mf.triangle_counts_by_material,
        recipe_counts: artifacts.material_model.recipe_counts,
        recipe_summaries: artifacts.material_model.recipe_summaries
      }
    end

    private

    def thickness_structure
      structure = @settings.layer_structure
      {
        base_white: structure.base_white_thickness,
        color_region: structure.color_region_thickness,
        minimum_top_white: structure.minimum_top_white_thickness,
        top_layer_height: structure.top_layer_height,
        minimum_total: structure.minimum_physical_thickness,
        effective_minimum: @settings.effective_minimum_thickness,
        effective_maximum: @settings.effective_maximum_thickness
      }
    end

    def z_part_separation
      structure = @settings.layer_structure
      boundaries = structure.z_boundaries(@settings.base_white_layers + @settings.color_layer_count)
      color_regions = structure.color_region_layer_ranges(@settings.color_region_parts)
                               .each_with_index.map do |range, index|
        {
          id: "color_region_#{index + 1}",
          layer_start: range.begin - @settings.base_white_layers + 1,
          layer_end: range.end - @settings.base_white_layers,
          z_min: boundaries.fetch(range.begin),
          z_max: boundaries.fetch(range.end)
        }
      end
      metadata = {
        enabled: @settings.separate_z_parts,
        base_white: { id: "base_white", z_min: 0.0, z_max: structure.base_white_thickness },
        color_regions:,
        top_white: {
          id: "top_white", z_min: structure.color_region_end,
          z_max: @settings.effective_maximum_thickness
        }
      }
      metadata[:plates] = z_plates(metadata) if @settings.separate_z_parts
      metadata
    end

    def z_plates(metadata)
      base_white = metadata.fetch(:base_white)
      regions = metadata.fetch(:color_regions).map do |region|
        region.merge(z_min: base_white.fetch(:z_min), build_z_max: region.fetch(:z_max))
      end
      regions << metadata.fetch(:top_white)
      regions.each_with_index.map do |region, index|
        z_min = region.fetch(:z_min)
        z_max = region.fetch(:z_max)
        {
          plate_id: index + 1,
          name: plate_name(region.fetch(:id)),
          source_z_min: z_min,
          source_z_max: z_max,
          build_z_min: 0.0,
          build_z_max: (region[:build_z_max] || (z_max - z_min)).round(9)
        }
      end
    end

    def plate_name(id)
      return "Top White" if id == "top_white"

      id.sub("color_region_", "Color region ")
    end

    def used_materials(artifacts)
      Palette::MATERIALS.select { |material| artifacts.material_model.materials.include?(material) }
    end

    def luminance_method
      return "measured_white_luminance" if @calibration.profile

      "normalized_material_display_density_or_rec601_luminance_continuous"
    end

    def material_names(materials)
      materials.map { |material| material.to_s.capitalize }
    end
  end
end

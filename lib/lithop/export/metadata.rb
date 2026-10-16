# frozen_string_literal: true

require "digest"
require "json"

module Lithop
  # Builds and writes the resolved settings and export manifest.
  # rubocop:disable-next Metrics/ClassLength
  class ExportMetadata
    def initialize(settings:, input_settings_path:, calibration:)
      @settings = settings
      @input_settings_path = input_settings_path
      @calibration = calibration
      @color_metadata = ExportColorMetadata.new(settings:, calibration:)
    end

    def write(directory:, source:, job_id:, artifacts:)
      resolved_settings = @settings.to_h.merge(
        schema_version: 1,
        generator_version: Lithop::VERSION,
        input_path: source,
        input_settings_path: @input_settings_path,
        calibration_profile_id: @calibration.profile&.profile_id,
        calibration_profile_path: @calibration.path
      )
      manifest = manifest_for(source, job_id, artifacts)
      write_json(File.join(directory, "settings.json"), resolved_settings)
      write_json(File.join(directory, "manifest.json"), manifest)
    end

    private

    # rubocop:disable-next Metrics/MethodLength
    def manifest_for(source, job_id, artifacts)
      {
        schema_version: 1,
        job_id:,
        units: "mm",
        viewing_direction: "+Z",
        image_top: "+Y",
        dimensions_mm: {
          width: @settings.width,
          height: @settings.height,
          depth: @settings.effective_maximum_thickness
        },
        print_settings: {
          nozzle_diameter_mm: @settings.nozzle_diameter,
          first_layer_height_mm: @settings.first_layer_height,
          layer_height_mm: @settings.layer_height
        },
        input_sha256: Digest::SHA256.file(source).hexdigest,
        filament_profile: FilamentProfile.default.to_h,
        tile_layout: tile_layout_metadata(artifacts),
        tiles: tile_metadata(artifacts),
        parts: [
          { file: artifacts.stl_name, material: "White", role: "monochrome_reference" },
          *artifacts.tile_artifacts.map do |artifact|
            tile_materials = Palette::MATERIALS.select do |material|
              artifact.material_model.materials.include?(material)
            end
            {
              file: artifact.name,
              tile_id: artifact.tile.id,
              materials: material_names(tile_materials),
              role: artifacts.tile_artifacts.one? ? "cmyw_lithophane" : "cmyw_lithophane_tile"
            }
          end
        ],
        color_model: @color_metadata.call(artifacts),
        files: artifact_files(artifacts),
        triangle_count: artifacts.stl_triangle_count,
        three_mf_triangle_count: artifacts.three_mf.triangle_count
      }
    end

    def artifact_files(artifacts)
      files = [
        artifacts.stl_name, *artifacts.three_mf_names, "settings.json", "manifest.json",
        "preview.png", "transmission.png", "thickness.png",
        *Palette::MATERIALS.map { |material| "#{material}-mask.png" }, "PRINT_README.md"
      ]
      files << "tile-layout.svg" if artifacts.tile_artifacts.length > 1
      files << "calibration-profile.json" if @calibration.profile
      files
    end

    def tile_layout_metadata(artifacts)
      {
        requested: @settings.tile_layout,
        tile_count: @settings.tile_count,
        rows: artifacts.tile_layout.rows,
        columns: artifacts.tile_layout.columns,
        order: "left_to_right_then_top_to_bottom",
        local_origin: "xy_min",
        assembled_image_top: "+Y"
      }
    end

    def tile_metadata(artifacts)
      artifacts.tile_artifacts.map do |artifact|
        tile = artifact.tile
        used = Palette::MATERIALS.select { |material| artifact.material_model.materials.include?(material) }
        {
          id: tile.id,
          file: artifact.name,
          row: tile.row,
          column: tile.column,
          offset_mm: tile.offset,
          bounds_mm: tile.bounds,
          dimensions_mm: { width: tile.width, height: tile.height, depth: @settings.effective_maximum_thickness },
          materials: material_names(used),
          unused_materials: material_names(Palette::MATERIALS - used),
          triangle_count: artifact.three_mf.triangle_count
        }
      end
    end

    def used_materials(artifacts)
      Palette::MATERIALS.select { |material| artifacts.material_model.materials.include?(material) }
    end

    def material_names(materials)
      materials.map { |material| material.to_s.capitalize }
    end

    def write_json(path, value)
      File.write(path, "#{JSON.pretty_generate(value)}\n")
    end
  end
end

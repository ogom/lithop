# frozen_string_literal: true

module Lithop
  # Runs the image, mesh, preview, and metadata stages for one regular export.
  # rubocop:disable-next Metrics/ClassLength
  class ExportGeneration
    Result = Data.define(:files, :triangle_count, :three_mf_triangle_count, :material_count, :object_count)
    TileEstimate = Data.define(:triangle_count, :triangle_counts_by_material)
    PlannedTile = Data.define(:tile, :material_model, :mesh_plan, :estimate)

    def initialize(settings:, input_settings_path:, calibration:, progress:, job_progress:, instrumentation:)
      @settings = settings
      @input_settings_path = input_settings_path
      @calibration_context = ExportCalibration.new(settings:, input: calibration)
      @progress = progress
      @job_progress = job_progress
      @instrumentation = Instrumentation.new(instrumentation)
      @metadata = ExportMetadata.new(
        settings:, input_settings_path:, calibration: @calibration_context
      )
    end

    def call(source:, directory:, job_id:)
      report_job_progress(:image_processing, 5, "Processing input image")
      image = @instrumentation.measure(:image_processing) { ImagePipeline.new(@settings).call(source) }
      report_job_progress(:height_selection, 20, "Selecting White heights")
      white_heights = @instrumentation.measure(:height_selection) do
        @calibration_context.heights(image.white_densities)
      end
      geometry = white_geometry(white_heights)
      report_job_progress(:material_model, 30, "Building CMYW material model")
      material_model = @instrumentation.measure(:material_model) do
        MaterialModel.new(
          cmys: image.cmys, cell_cmys: image.color_cells,
          heights: white_heights, settings: @settings, palette: @calibration_context.palette
        )
      end
      tile_layout = TileLayout.new(@settings)
      report_job_progress(:triangle_planning, 40, "Planning mesh triangles")
      planned_tiles = @instrumentation.measure(:triangle_planning) do
        plan_tiles(tile_layout, material_model, white_heights)
      end
      tile_estimates = planned_tiles.map(&:estimate)
      validate_total_triangle_count!(tile_estimates)
      report_estimate(tile_estimates)
      report_job_progress(:artifact_write, 50, "Writing model artifacts")
      artifacts = write_artifacts(
        directory, geometry, material_model, tile_layout, planned_tiles, white_heights, image.corrected_preview_png
      )
      report_job_progress(:metadata_write, 95, "Writing job metadata")
      write_supporting_files(directory, source, job_id, artifacts)
      result_for(directory, artifacts)
    end

    private

    def white_geometry(heights)
      Geometry.new(
        heights:,
        columns: @settings.columns,
        rows: @settings.rows,
        x_boundaries: @settings.x_boundaries,
        y_boundaries: @settings.y_boundaries,
        optimize_bottom: true
      )
    end

    def material_mesh_plan(material_model, white_geometry)
      ReferenceMaterialMeshPlan.new(
        model: material_model,
        white_geometry:,
        maximum_triangles: @settings.maximum_triangles,
        limit_message: ->(count) { @settings.triangle_limit_message("physical CMYW mesh", count) }
      ).call
    end

    def plan_tiles(tile_layout, material_model, white_heights)
      tile_layout.tiles.map do |tile|
        tile_model, mesh_plan = @instrumentation.measure(:tile_plan_estimate) do
          build_tile_plan(tile, material_model, white_heights)
        end
        estimate = TileEstimate.new(
          triangle_count: mesh_plan.triangle_count,
          triangle_counts_by_material: mesh_plan.triangle_counts_by_material
        )
        PlannedTile.new(tile:, material_model: tile_model, mesh_plan:, estimate:)
      end
    end

    def build_tile_plan(tile, material_model, white_heights)
      tile_model = TileMaterialModel.new(model: material_model, tile:)
      plan = if @settings.separate_z_parts
               top_geometry = tile_white_geometry(
                 tile, tile_model, white_heights,
                 base_height: [
                   @settings.layer_structure.color_region_end,
                   @settings.resolved_z_part_ranges.last.begin
                 ].max,
                 minimum_height: @settings.effective_minimum_thickness
               )
               z_separated_material_mesh_plan(tile_model, top_geometry)
             else
               geometry = tile_white_geometry(tile, tile_model, white_heights)
               material_mesh_plan(tile_model, geometry)
             end
      [tile_model, plan]
    end

    def tile_white_geometry(tile, model, heights, base_height: 0.0, minimum_height: nil)
      stride = @settings.columns + 1
      sliced_heights = (tile.row_start..tile.row_end).flat_map do |row|
        heights.slice((row * stride) + tile.column_start, model.columns + 1)
      end
      sliced_heights.map! { |height| [height, minimum_height].max } if minimum_height
      Geometry.new(
        heights: sliced_heights,
        columns: model.columns,
        rows: model.rows,
        x_boundaries: model.x_boundaries,
        y_boundaries: model.y_boundaries,
        optimize_bottom: true,
        base_height:
      )
    end

    def z_separated_material_mesh_plan(model, top_geometry)
      ZSeparatedMaterialMeshPlan.new(
        model:, top_geometry:, settings: @settings,
        maximum_triangles: @settings.maximum_triangles,
        limit_message: ->(count) { @settings.triangle_limit_message("physical Z-separated CMYW mesh", count) }
      ).call
    end

    def validate_total_triangle_count!(tile_estimates)
      count = tile_estimates.sum(&:triangle_count)
      return if count <= @settings.maximum_triangles

      raise ConfigurationError, @settings.triangle_limit_message("physical CMYW tiled mesh", count)
    end

    # rubocop:disable-next Metrics/ParameterLists
    def write_artifacts(directory, geometry, material_model, tile_layout, planned_tiles, white_heights, corrected_input)
      stl_name = "cmyk_white.stl"
      triangle_count = @instrumentation.measure(:stl_write) do
        STL.write(File.join(directory, stl_name), geometry.each_triangle)
      end
      FileUtils.mkdir_p(File.join(directory, "tiles")) if tile_layout.tiles.length > 1
      tile_artifacts = planned_tiles.each_with_index.map do |planned, index|
        tile = planned.tile
        percent = 60 + ((index * 20.0) / planned_tiles.length)
        report_job_progress(:three_mf_write, percent, "Writing 3MF tile #{index + 1}/#{planned_tiles.length}")
        name = tile_layout.tiles.one? ? "lithop.3mf" : "tiles/#{tile.id}.3mf"
        three_mf = @instrumentation.measure(:three_mf_write) do
          ThreeMF.write(
            File.join(directory, name), parts: planned.mesh_plan.parts, instrumentation: @instrumentation,
                                        settings: @settings
          )
        end
        planned.mesh_plan.validate!(three_mf)
        TileArtifact.new(tile:, name:, three_mf:, material_model: planned.material_model)
      end
      if tile_layout.tiles.length > 1
        TileLayoutSVG.write(File.join(directory, "tile-layout.svg"), settings: @settings, layout: tile_layout)
      end
      report_job_progress(:preview_write, 85, "Writing previews")
      @instrumentation.measure(:preview_write) do
        write_previews(directory, material_model, tile_artifacts, white_heights, corrected_input)
      end
      ExportArtifacts.new(
        stl_name:,
        tile_artifacts:,
        stl_triangle_count: triangle_count,
        material_model:,
        tile_layout:
      )
    end

    def write_previews(directory, material_model, tile_artifacts, white_heights, corrected_input)
      ExportPreviews.write(
        directory, model: material_model, settings: @settings, white_heights:, corrected_input:
      )
      ExportPreviews.write_tiles(directory, tile_artifacts:, settings: @settings, white_heights:)
    end

    def write_supporting_files(directory, source, job_id, artifacts)
      @instrumentation.measure(:metadata_write) do
        @calibration_context.write(directory)
        @metadata.write(directory:, source:, job_id:, artifacts:)
        PrintReadme.write(
          File.join(directory, "PRINT_README.md"),
          settings: @settings,
          material_model: artifacts.material_model,
          calibration_profile: @calibration_context.profile,
          tile_artifacts: artifacts.tile_artifacts
        )
      end
    end

    def report_estimate(tile_estimates)
      return unless @progress

      counts = tile_estimates.each_with_object(Hash.new(0)) do |estimate, totals|
        estimate.triangle_counts_by_material.each { |material, count| totals[material] += count }
      end

      @progress.call(
        Export::Estimate.new(
          stl_triangle_count: @settings.estimated_triangles,
          three_mf_triangle_count: tile_estimates.sum(&:triangle_count),
          triangle_counts_by_material: counts.freeze
        )
      )
    end

    def report_job_progress(phase, percent, message)
      @job_progress&.call(phase:, percent:, message:)
    end

    def result_for(directory, artifacts)
      three_mf = artifacts.three_mf
      Result.new(
        files: Dir.glob("**/*", base: directory).select { |name| File.file?(File.join(directory, name)) }.sort,
        triangle_count: artifacts.stl_triangle_count,
        three_mf_triangle_count: three_mf.triangle_count,
        material_count: three_mf.material_count,
        object_count: three_mf.object_count
      )
    end
  end
end

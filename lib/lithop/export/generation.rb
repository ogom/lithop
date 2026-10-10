# frozen_string_literal: true

module Lithop
  # Runs the image, mesh, preview, and metadata stages for one regular export.
  # rubocop:disable-next Metrics/ClassLength
  class ExportGeneration
    Result = Data.define(:files, :triangle_count, :three_mf_triangle_count, :material_count, :object_count)

    def initialize(settings:, input_settings_path:, calibration:, progress:, instrumentation:)
      @settings = settings
      @input_settings_path = input_settings_path
      @calibration_context = ExportCalibration.new(settings:, input: calibration)
      @progress = progress
      @instrumentation = Instrumentation.new(instrumentation)
      @metadata = ExportMetadata.new(
        settings:, input_settings_path:, calibration: @calibration_context
      )
    end

    def call(source:, directory:, job_id:)
      image = @instrumentation.measure(:image_processing) { ImagePipeline.new(@settings).call(source) }
      white_heights = @instrumentation.measure(:height_selection) do
        @calibration_context.heights(image.white_densities)
      end
      geometry = white_geometry(white_heights)
      material_model = @instrumentation.measure(:material_model) do
        MaterialModel.new(
          cmys: image.cmys, cell_cmys: image.color_cells,
          heights: white_heights, settings: @settings, palette: @calibration_context.palette
        )
      end
      mesh_plan = @instrumentation.measure(:triangle_planning) { material_mesh_plan(material_model, geometry) }
      report_estimate(mesh_plan)
      artifacts = write_artifacts(directory, geometry, material_model, mesh_plan, white_heights)
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

    def write_artifacts(directory, geometry, material_model, mesh_plan, white_heights)
      stl_name = "cmyk_white.stl"
      triangle_count = @instrumentation.measure(:stl_write) do
        STL.write(File.join(directory, stl_name), geometry.each_triangle)
      end
      three_mf_name = "lithop.3mf"
      three_mf = @instrumentation.measure(:three_mf_write) do
        ThreeMF.write(
          File.join(directory, three_mf_name), parts: mesh_plan.parts, instrumentation: @instrumentation,
                                               settings: @settings
        )
      end
      mesh_plan.validate!(three_mf)
      @instrumentation.measure(:preview_write) do
        ExportPreviews.write(directory, model: material_model, settings: @settings, white_heights:)
      end
      ExportArtifacts.new(
        stl_name:,
        three_mf_name:,
        stl_triangle_count: triangle_count,
        three_mf:,
        material_model:
      )
    end

    def write_supporting_files(directory, source, job_id, artifacts)
      @instrumentation.measure(:metadata_write) do
        @calibration_context.write(directory)
        @metadata.write(directory:, source:, job_id:, artifacts:)
        PrintReadme.write(
          File.join(directory, "PRINT_README.md"),
          settings: @settings,
          material_model: artifacts.material_model,
          calibration_profile: @calibration_context.profile
        )
      end
    end

    def report_estimate(plan)
      return unless @progress

      @progress.call(
        Export::Estimate.new(
          stl_triangle_count: @settings.estimated_triangles,
          three_mf_triangle_count: plan.triangle_count,
          triangle_counts_by_material: plan.triangle_counts_by_material
        )
      )
    end

    def result_for(directory, artifacts)
      three_mf = artifacts.three_mf
      Result.new(
        files: Dir.children(directory).sort,
        triangle_count: artifacts.stl_triangle_count,
        three_mf_triangle_count: three_mf.triangle_count,
        material_count: three_mf.material_count,
        object_count: three_mf.object_count
      )
    end
  end
end

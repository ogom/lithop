# frozen_string_literal: true

require "json"
require "securerandom"
require "time"

module Lithop
  module Calibration
    # Exports a printable calibration target and its measurement profile.
    class Export
      Result = Data.define(:job_id, :path, :files, :triangle_count, :patch_count)

      def initialize(settings:, project_dir:, clock: Time, random: SecureRandom)
        @settings = settings
        @project_dir = File.expand_path(project_dir)
        @clock = clock
        @random = random
      end

      def call
        job_id = "#{@clock.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{@random.hex(4)}-calibration"
        destination, generated = JobDirectory.new(project_dir: @project_dir, job_id:).call do |directory|
          generate(directory, job_id)
        end
        Result.new(job_id:, path: destination, files: generated.fetch(:files),
                   triangle_count: generated.fetch(:triangle_count), patch_count: generated.fetch(:patch_count))
      end

      private

      def generate(directory, job_id)
        target = Target.new(settings: @settings)
        result = write_three_mf(File.join(directory, "calibration.3mf"), target)
        TargetSVG.write(File.join(directory, "calibration.svg"), target)
        profile = Profile.template(profile_id: job_id, settings: @settings, target:)
        profile.write(File.join(directory, "calibration-profile.json"))
        write_manifest(directory, job_id, target, result)
        write_readme(directory, target)
        {
          files: Dir.children(directory).sort,
          triangle_count: result.triangle_count,
          patch_count: target.patches.length
        }
      end

      def write_three_mf(path, target)
        plan = MaterialMeshPlan.new(
          model: target,
          maximum_triangles: @settings.maximum_triangles,
          label: "calibration mesh"
        ).call
        result = ThreeMF.write(path, parts: plan.parts)
        plan.validate!(result)

        result
      end

      def write_manifest(directory, job_id, target, result)
        manifest = {
          schema_version: 1,
          artifact_type: "calibration_target",
          job_id:,
          generator_version: Lithop::VERSION,
          structure: Profile.structure_for(@settings),
          layout: {
            width_mm: target.width, height_mm: target.height,
            patch_width_mm: target.x_boundaries[1], patch_height_mm: target.y_boundaries[1],
            columns: target.columns, rows: target.rows
          },
          recipe_patch_count: target.recipe_patches.length,
          white_thickness_patch_count: target.white_patches.length,
          triangle_count: result.triangle_count,
          material_count: result.material_count,
          object_count: result.object_count
        }
        File.write(File.join(directory, "manifest.json"), "#{JSON.pretty_generate(manifest)}\n")
      end

      def write_readme(directory, target)
        contents = <<~MARKDOWN
          # Calibration target

          Use `calibration.svg` to review the patch IDs and layout. Print `calibration.3mf` without changing
          its dimensions, layer heights, or material order. The plate is #{target.width} × #{target.height} mm.

          - nozzle: #{@settings.nozzle_diameter} mm
          - first layer: #{@settings.first_layer_height} mm
          - later layers: #{@settings.layer_height} mm
          - pigment order: #{@settings.pigment_order.join(" -> ")}

          - `R000`–`R119`: all 120 standard seven-layer CMYW recipes, row-major from the upper-left corner
          - `W00`–`W07`: White thickness stages from left to right on the bottom row
          - the extra right column makes the plate orientation unambiguous

          Add repeated transmitted-sRGB and luminance readings to each patch's `measurements` array in
          `calibration-profile.json`. Record white and black references in the top-level `measurement` object.
        MARKDOWN
        File.write(File.join(directory, "CALIBRATION_README.md"), contents)
      end
    end
  end
end

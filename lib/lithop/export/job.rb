# frozen_string_literal: true

require "securerandom"
require "time"

module Lithop
  # Coordinates image processing, mesh generation, and artifact export.
  class Export
    CalibrationInput = Data.define(:profile, :path)
    Estimate = Data.define(:stl_triangle_count, :three_mf_triangle_count, :triangle_counts_by_material)

    Result = ExportResult

    # Dependency injection keeps job IDs testable; generation options remain explicit keywords.
    # rubocop:disable-next Metrics/ParameterLists
    def initialize(
      settings:, project_dir:, input_settings_path: nil, calibration: nil, progress: nil,
      instrumentation: nil, clock: Time, random: SecureRandom
    )
      @settings = settings
      @project_dir = File.expand_path(project_dir)
      @input_settings_path = input_settings_path
      @calibration = calibration
      @progress = progress
      @clock = clock
      @random = random
      @generation = ExportGeneration.new(
        settings:, input_settings_path:, calibration:, progress:, instrumentation:
      )
    end

    def call(input_path)
      source = File.expand_path(input_path)
      job_id = "#{@clock.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{@random.hex(4)}"
      destination, result = JobDirectory.new(project_dir: @project_dir, job_id:).call do |directory|
        @generation.call(source:, directory:, job_id:)
      end
      Result.new(
        job_id:,
        path: destination,
        files: result.files,
        triangle_count: result.triangle_count,
        three_mf_triangle_count: result.three_mf_triangle_count,
        material_count: result.material_count,
        object_count: result.object_count
      )
    end
  end
end

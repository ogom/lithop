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
      job_progress: nil, instrumentation: nil, clock: Time, random: SecureRandom, job_id: nil
    )
      @settings = settings
      @project_dir = File.expand_path(project_dir)
      @input_settings_path = input_settings_path
      @calibration = calibration
      @progress = progress
      @job_progress = job_progress
      @clock = clock
      @random = random
      @instrumentation = instrumentation
      @job_id = job_id
    end

    def call(input_path)
      source = File.expand_path(input_path)
      job_id = @job_id || "#{@clock.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{@random.hex(4)}"
      execution = JobExecution.new(
        project_dir: @project_dir, job_id:, progress: @job_progress, clock: @clock
      )
      execution.call do |job|
        generation = ExportGeneration.new(
          settings: @settings,
          input_settings_path: @input_settings_path,
          calibration: @calibration,
          progress: @progress,
          job_progress: job.method(:progress),
          instrumentation: @instrumentation
        )
        destination, generated = JobDirectory.new(project_dir: @project_dir, job_id:).call do |directory|
          generation.call(source:, directory:, job_id:).tap { job.checkpoint! }
        end
        job.publication_committed!
        Result.new(
          job_id:,
          path: destination,
          files: generated.files,
          triangle_count: generated.triangle_count,
          three_mf_triangle_count: generated.three_mf_triangle_count,
          material_count: generated.material_count,
          object_count: generated.object_count
        )
      end
    end
  end
end

# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../lib/lithop"

module Lithop
  # Collects repeatable generation metrics for the benchmark rake task.
  module BenchmarkTask
    module_function

    def measure(image, settings)
      Dir.mktmpdir("lithop-benchmark-") do |directory|
        stages = {}
        estimate = nil
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Export.new(
          settings:,
          project_dir: directory,
          progress: ->(value) { estimate = value },
          instrumentation: ->(stage, seconds) { stages[stage] = stages.fetch(stage, 0.0) + seconds }
        ).call(image)
        measurement(result, estimate, stages, started)
      end
    end

    def measurement(result, estimate, stages, started)
      {
        elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        stages:,
        stl_triangles: result.triangle_count,
        three_mf_triangles: result.three_mf_triangle_count,
        triangle_counts_by_material: estimate.triangle_counts_by_material,
        stl_bytes: File.size(File.join(result.path, "cmyk_white.stl")),
        three_mf_bytes: File.size(File.join(result.path, "lithop.3mf"))
      }
    end
  end
end

namespace :benchmark do
  desc "Measure Lithop generation stages (IMAGE WIDTH HEIGHT PIXEL_SIZE RUNS COLOR_PIXEL_SIZE)"
  task :generate, %i[image width height pixel_size runs color_pixel_size] do |_task, arguments|
    image = File.expand_path(arguments.fetch(:image, "examples/cmyw.png"))
    width = Float(arguments.fetch(:width, 36))
    height = Float(arguments.fetch(:height, 27))
    pixel_size = Float(arguments.fetch(:pixel_size, 0.5))
    runs = Integer(arguments.fetch(:runs, 3))
    color_pixel_size = arguments[:color_pixel_size]&.then { |value| Float(value) }
    settings = Lithop::Settings.new(width:, height:, pixel_size:, color_pixel_size:)
    measurements = Array.new(runs) { Lithop::BenchmarkTask.measure(image, settings) }
    puts JSON.pretty_generate(
      image:, width:, height:, pixel_size:, color_pixel_size: settings.effective_color_pixel_size,
      columns: settings.columns, rows: settings.rows,
      color_columns: settings.color_sampling_grid.columns, color_rows: settings.color_sampling_grid.rows,
      nozzle_diameter: settings.nozzle_diameter,
      color_layer_count: settings.color_layer_count,
      pigment_order: settings.pigment_order,
      runs: measurements
    )
  end
end

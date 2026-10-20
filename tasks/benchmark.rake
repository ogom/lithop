# frozen_string_literal: true

require "json"
require "digest"
require "open3"
require "rbconfig"
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
        gc_before = GC.stat
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = Export.new(
          settings:,
          project_dir: directory,
          progress: ->(value) { estimate = value },
          instrumentation: ->(stage, seconds) { stages[stage] = stages.fetch(stage, 0.0) + seconds }
        ).call(image)
        measurement(result, estimate, stages, started, gc_before)
      end
    end

    def measurement(result, estimate, stages, started, gc_before)
      gc_after = GC.stat
      three_mf_files = result.files.grep(/\.3mf\z/)
      {
        elapsed_seconds: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        stages:,
        gc: {
          count: gc_after.fetch(:count) - gc_before.fetch(:count),
          time_ms: gc_after.fetch(:time) - gc_before.fetch(:time),
          allocated_objects: gc_after.fetch(:total_allocated_objects) - gc_before.fetch(:total_allocated_objects)
        },
        stl_triangles: result.triangle_count,
        three_mf_triangles: result.three_mf_triangle_count,
        triangle_counts_by_material: estimate.triangle_counts_by_material,
        stl_bytes: File.size(File.join(result.path, "cmyk_white.stl")),
        three_mf_files: three_mf_files.to_h { |name| [name, File.size(File.join(result.path, name))] },
        three_mf_bytes: three_mf_files.sum { |name| File.size(File.join(result.path, name)) }
      }
    end

    def environment(image, settings)
      {
        input_sha256: Digest::SHA256.file(image).hexdigest,
        ruby: RUBY_DESCRIPTION,
        rust: command_output("rustc", "--version"),
        platform: RbConfig::CONFIG.fetch("host"),
        git_commit: command_output("git", "rev-parse", "HEAD"),
        git_dirty: !command_output("git", "status", "--porcelain").empty?,
        settings: settings.to_h
      }
    end

    def command_output(*command)
      stdout, status = Open3.capture2e(*command, chdir: File.expand_path("..", __dir__))
      status.success? ? stdout.strip : nil
    rescue SystemCallError
      nil
    end

    def subprocess_generation(image:, width:, height:, pixel_size:, backend:)
      task = "benchmark:generate[#{image},#{width},#{height},#{pixel_size},1]"
      command = ["/usr/bin/time", "-l", RbConfig.ruby, Gem.bin_path("rake", "rake"), task]
      environment = { "LITHOP_DISABLE_NATIVE" => backend == "ruby" ? "1" : nil }
      stdout, stderr, status = Open3.capture3(
        environment, *command, chdir: File.expand_path("..", __dir__)
      )
      payload = JSON.parse(stdout)
      raise "benchmark subprocess failed: #{stderr}" unless status.success? || payload["runs"]

      payload.fetch("runs").first.merge(
        "maximum_rss_bytes" => stderr[/\s*(\d+)\s+maximum resident set size/, 1]&.then { |value| Integer(value) }
      )
    end

    def summarize(measurements)
      elapsed = measurements.map { |measurement| measurement.fetch("elapsed_seconds") }.sort
      rss = measurements.filter_map { |measurement| measurement["maximum_rss_bytes"] }.sort
      rss_summary = ({ "median" => median(rss), "minimum" => rss.first, "maximum" => rss.last } unless rss.empty?)
      {
        "elapsed_seconds" => { "median" => median(elapsed), "minimum" => elapsed.first, "maximum" => elapsed.last },
        "maximum_rss_bytes" => rss_summary
      }
    end

    def median(values)
      middle = values.length / 2
      values.length.odd? ? values.fetch(middle) : (values.fetch(middle - 1) + values.fetch(middle)).fdiv(2)
    end

    def measure_palette(palette, cmys, runs, backend)
      return if backend == "rust" && !Native.available?

      previous = ENV.fetch("LITHOP_DISABLE_NATIVE", nil)
      ENV["LITHOP_DISABLE_NATIVE"] = backend == "ruby" ? "1" : nil
      Array.new(runs) do
        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        palette.nearest_many(cmys)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      end
    ensure
      ENV["LITHOP_DISABLE_NATIVE"] = previous if defined?(previous)
    end
  end
end

# rubocop:disable-next Metrics/BlockLength
namespace :benchmark do
  desc "Measure generation " \
       "(IMAGE WIDTH HEIGHT PIXEL_SIZE RUNS COLOR_PIXEL_SIZE TILES LAYOUT ROWS COLUMNS Z_PARTS COLOR_PARTS)"
  task :generate, %i[
    image width height pixel_size runs color_pixel_size tile_count tile_layout tile_rows tile_columns
    separate_z_parts color_region_parts
  ] do |_task, arguments|
    image = File.expand_path(arguments.fetch(:image, "examples/cmy-fine-line.svg"))
    width = Float(arguments.fetch(:width, 36))
    height = Float(arguments.fetch(:height, 27))
    pixel_size = Float(arguments.fetch(:pixel_size, 0.5))
    runs = Integer(arguments.fetch(:runs, 3))
    color_pixel_size = arguments[:color_pixel_size]&.then { |value| Float(value) }
    tile_count = Integer(arguments.fetch(:tile_count, 1))
    tile_layout = arguments.fetch(:tile_layout, "auto")
    tile_rows = arguments[:tile_rows]&.then { |value| Integer(value) }
    tile_columns = arguments[:tile_columns]&.then { |value| Integer(value) }
    separate_z_parts = arguments.fetch(:separate_z_parts, "false") == "true"
    color_region_parts = Integer(arguments.fetch(:color_region_parts, 3))
    settings = Lithop::Settings.new(
      width:, height:, pixel_size:, color_pixel_size:, tile_count:, tile_layout:, tile_rows:, tile_columns:,
      separate_z_parts:, color_region_parts:
    )
    measurements = Array.new(runs) { Lithop::BenchmarkTask.measure(image, settings) }
    puts JSON.pretty_generate(
      image:, environment: Lithop::BenchmarkTask.environment(image, settings),
      native_backend: Lithop::Native.backend,
      runs: measurements
    )
  end

  desc "Compare Ruby and Rust palette selection (SAMPLES RUNS)"
  task :palette, %i[samples runs] do |_task, arguments|
    sample_count = Integer(arguments.fetch(:samples, 300_000))
    runs = Integer(arguments.fetch(:runs, 5))
    random = Random.new(20_261_019)
    cmys = Array.new(sample_count) { [random.rand, random.rand, random.rand] }
    palette = Lithop::Palette.new
    measurements = %w[ruby rust].to_h do |backend|
      [backend, Lithop::BenchmarkTask.measure_palette(palette, cmys, runs, backend)]
    end
    puts JSON.pretty_generate(samples: sample_count, runs:, seconds: measurements)
  end

  desc "Compare Ruby and Rust generation in independent processes (IMAGE WIDTH HEIGHT PIXEL_SIZE RUNS)"
  task :compare, %i[image width height pixel_size runs] do |_task, arguments|
    image = File.expand_path(arguments.fetch(:image, "examples/cmy-color-chart.svg"))
    width = Float(arguments.fetch(:width, 140))
    height = Float(arguments.fetch(:height, 104))
    pixel_size = Float(arguments.fetch(:pixel_size, 0.22))
    runs = Integer(arguments.fetch(:runs, 5))
    measurements = %w[ruby rust].to_h do |backend|
      values = Array.new(runs) do
        Lithop::BenchmarkTask.subprocess_generation(image:, width:, height:, pixel_size:, backend:)
      end
      [backend, { "summary" => Lithop::BenchmarkTask.summarize(values), "runs" => values }]
    end
    puts JSON.pretty_generate(image:, width:, height:, pixel_size:, runs:, backends: measurements)
  end
end

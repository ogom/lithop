# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"
require "time"
require "vips"
require "lithop"
require "lithop/web/app"

FileUtils.mkdir_p("tmp")
$stdout.reopen("tmp/playwright-server.log", "w")
$stdout.sync = true
$stderr.reopen($stdout)

# rubocop:disable-next Metrics/ClassLength
class BrowserTestLauncher
  def initialize(project_dir)
    @project_dir = project_dir
    @sequence = 0
  end

  def start(upload:, filename:, settings:)
    upload.read
    @sequence += 1
    job_id = "browser-job-#{@sequence}"
    jobs = File.join(@project_dir, "build", ".jobs")
    FileUtils.mkdir_p(jobs)
    write_json(
      File.join(jobs, "#{job_id}.request.json"),
      { input_name: filename }.merge(settings.to_h.slice(*Lithop::Settings::DEFAULTS.keys))
    )
    write_status(job_id, state: "running", phase: "image_processing", percent: 10, message: "Processing input image")
    Thread.new do
      sleep filename.include?("failure") ? 0.25 : 1.5
      if active?(job_id)
        filename.include?("failure") ? fail_job(job_id) : complete(job_id)
      end
    end
    job_id
  end

  def cancel(job_id)
    write_status(job_id, state: "cancelled", phase: "cancelled", percent: 10, message: "Conversion cancelled")
  end

  def active?(job_id)
    record = read_status(job_id)
    record && %w[queued running cancelling].include?(record["state"])
  end

  def seed_history(count:, tile_count:)
    jobs = File.join(@project_dir, "build", ".jobs")
    FileUtils.mkdir_p(jobs)
    preview = File.join(@project_dir, "build", ".seed-preview.png")
    Vips::Image.black(16, 12).new_from_image([0, 134, 214]).pngsave(preview)
    count.times do |index|
      job_id = format("browser-seed-%03d", index)
      output = File.join(@project_dir, "build", job_id)
      FileUtils.mkdir_p(output)
      FileUtils.cp(preview, File.join(output, "preview.png"))
      File.write(File.join(output, "lithop.3mf"), "browser fixture")
      write_json(
        File.join(jobs, "#{job_id}.request.json"),
        { input_name: format("seed-history-%03d.png", index), width: 140.0, height: 104.0, tile_count: 1 }
      )
      write_status(
        job_id, state: "completed", phase: "completed", percent: 100, message: "Conversion completed",
                output_path: output, files: ["preview.png", "lithop.3mf"]
      )
    end
    seed_tiled_job(tile_count, preview)
    FileUtils.rm_f(preview)
    { jobs: count, tiles: tile_count }
  end

  private

  def seed_tiled_job(tile_count, preview)
    job_id = "browser-seed-tiles"
    output = File.join(@project_dir, "build", job_id)
    tiles = File.join(output, "tiles")
    jobs = File.join(@project_dir, "build", ".jobs")
    FileUtils.mkdir_p(tiles)
    metadata = tile_count.times.map do |index|
      id = format("tile_r01_c%02d", index + 1)
      File.write(File.join(tiles, "#{id}.3mf"), "browser fixture")
      FileUtils.cp(preview, File.join(tiles, "#{id}-preview.png"))
      {
        id:, file: "tiles/#{id}.3mf", preview_file: "tiles/#{id}-preview.png", row: 1, column: index + 1,
        offset_mm: { x: index.fdiv(tile_count) * 140, y: 0 },
        dimensions_mm: { width: 140.fdiv(tile_count), height: 104, depth: 2.1 }
      }
    end
    write_json(
      File.join(output, "manifest.json"),
      { tile_layout: { tile_count:, rows: 1, columns: tile_count }, tiles: metadata,
        color_model: { z_part_separation: { enabled: false } } }
    )
    files = Dir.glob("**/*", base: output).select { |name| File.file?(File.join(output, name)) }.sort
    write_json(
      File.join(jobs, "#{job_id}.request.json"),
      { input_name: "seed-tiles.png", width: 140.0, height: 104.0, tile_count: }
    )
    write_status(
      job_id, state: "completed", phase: "completed", percent: 100, message: "Conversion completed",
              output_path: output, files:
    )
  end

  def complete(job_id)
    output = File.join(@project_dir, "build", job_id)
    FileUtils.mkdir_p(output)
    write_previews(output)
    request = JSON.parse(File.read(File.join(@project_dir, "build", ".jobs", "#{job_id}.request.json")))
    request.fetch("tile_count", 1) > 1 ? write_tiles(output, request) : write_model(output)
    files = Dir.glob("**/*", base: output).select { |name| File.file?(File.join(output, name)) }.sort
    write_status(
      job_id, state: "completed", phase: "completed", percent: 100, message: "Conversion completed",
              output_path: output, files:
    )
  end

  def write_previews(output)
    %w[
      corrected-input.png preview.png transmission.png thickness.png
      cyan-mask.png magenta-mask.png yellow-mask.png white-mask.png
    ].each do |name|
      Vips::Image.black(32, 24).new_from_image([0, 134, 214]).pngsave(File.join(output, name))
    end
  end

  def write_model(output) = File.write(File.join(output, "lithop.3mf"), "browser fixture")

  def write_tiles(output, request)
    tiles = File.join(output, "tiles")
    FileUtils.mkdir_p(tiles)
    metadata = request.fetch("tile_count").times.map { |index| write_tile(tiles, request, index) }
    File.write(File.join(output, "tile-layout.svg"), '<svg xmlns="http://www.w3.org/2000/svg"></svg>')
    write_json(
      File.join(output, "manifest.json"),
      {
        tile_layout: { tile_count: request.fetch("tile_count"), rows: 1, columns: request.fetch("tile_count") },
        tiles: metadata, color_model: { z_part_separation: z_parts(request) }
      }
    )
  end

  def write_tile(directory, request, index)
    id = format("tile_r01_c%02d", index + 1)
    File.write(File.join(directory, "#{id}.3mf"), "browser fixture")
    Vips::Image.black(16, 24).new_from_image([0, 134, 214]).pngsave(File.join(directory, "#{id}-preview.png"))
    width = request.fetch("width").fdiv(request.fetch("tile_count"))
    {
      id:, file: "tiles/#{id}.3mf", preview_file: "tiles/#{id}-preview.png", row: 1, column: index + 1,
      offset_mm: { x: width * index, y: 0.0 },
      dimensions_mm: { width:, height: request.fetch("height"), depth: request.fetch("maximum_thickness") }
    }
  end

  def z_parts(request)
    return unless request.fetch("separate_z_parts", false)

    { enabled: true, color_regions: Array.new(3) { |index| { id: "color_region_#{index + 1}" } } }
  end

  def fail_job(job_id)
    File.write(File.join(@project_dir, "build", ".jobs", "#{job_id}.log"), "Browser fixture conversion failed\n")
    write_status(
      job_id, state: "failed", phase: "failed", percent: 10,
              message: "Conversion failed", error: { message: "Browser fixture conversion failed" }
    )
  end

  def write_status(job_id, **values)
    jobs = File.join(@project_dir, "build", ".jobs")
    previous = read_status(job_id) || {}
    now = Time.now.utc.iso8601(6)
    record = {
      schema_version: 1, job_id:, created_at: previous["created_at"] || now,
      updated_at: now, files: nil, error: nil
    }.merge(previous.transform_keys(&:to_sym)).merge(values)
    write_json(File.join(jobs, "#{job_id}.json"), record)
  end

  def read_status(job_id)
    JSON.parse(File.read(File.join(@project_dir, "build", ".jobs", "#{job_id}.json")))
  rescue Errno::ENOENT
    nil
  end

  def write_json(path, value)
    File.write(path, JSON.pretty_generate(value) << "\n")
  end
end

project_dir = Dir.mktmpdir("lithop-browser-")
launcher = BrowserTestLauncher.new(project_dir)
application = Lithop::Web::App.configured(project_dir:, launcher:, csrf_token: "browser-test-token")
application.get "/__test__/seed-history" do
  content_type :json
  JSON.generate(
    settings.launcher.seed_history(
      count: Integer(params.fetch("count", 60).to_s, 10),
      tile_count: Integer(params.fetch("tiles", 24).to_s, 10)
    )
  )
end
at_exit do
  FileUtils.rm_rf(project_dir)
  FileUtils.rm_f("tmp/playwright-port")
end
application.run!(bind: "127.0.0.1", port: Integer(ENV.fetch("LITHOP_BROWSER_PORT")), server: :puma)

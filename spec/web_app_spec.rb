# frozen_string_literal: true

require "json"
require "rack/mock"
require "rack/multipart"
require "tempfile"
require "lithop/web/app"

RSpec.describe Lithop::Web::App do
  def request_for(project_dir, launcher: nil, bambu_studio_launcher: nil)
    launcher ||= Class.new do
      attr_reader :request, :cancelled

      def start(**request)
        @request = request.merge(contents: request.fetch(:upload).read)
        "web-job"
      end

      def cancel(job_id) = @cancelled = job_id
    end.new
    bambu_studio_launcher ||= Class.new do
      attr_reader :opened

      def supported? = true
      def active?(_job_id) = false
      def open(**request) = @opened = request
    end.new
    application = described_class.configured(
      project_dir:, launcher:, bambu_studio_launcher:, csrf_token: "test-token"
    )
    [Rack::MockRequest.new(application), launcher, bambu_studio_launcher]
  end

  it "serves the bundled form and static assets with local UI security headers" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)

      page = request.get("/", "HTTP_HOST" => "127.0.0.1")
      stylesheet = request.get("/app.css", "HTTP_HOST" => "127.0.0.1")
      javascript = request.get("/app.js", "HTTP_HOST" => "127.0.0.1")

      expect(page.status).to eq(200)
      expect(page.body).to include("Lithop", "multipart/form-data", "test-token")
      expect(page["content-security-policy"]).to include("default-src 'self'")
      expect(page["content-security-policy"]).to include("style-src-attr 'unsafe-inline'")
      expect(stylesheet.status).to eq(200)
      expect(stylesheet.body).to include("--cyan: #0086d6")
      expect(javascript.status).to eq(200)
      expect(javascript.body).to include(
        'form?.addEventListener("submit", async (event) =>',
        'fetch("/jobs", { method: "POST", headers: { Accept: "application/json" }, body: data })'
      )
      expect(javascript.body).not_to include("requestSubmit()")
    end
  end

  it "validates a multipart form and starts a conversion with common settings" do
    Dir.mktmpdir do |project_dir|
      request, launcher = request_for(project_dir)
      input = Tempfile.new(["input", ".png"])
      input.write("image")
      input.close
      upload = Rack::Multipart::UploadedFile.new(input.path, "image/png", filename: "input.png")
      body = Rack::Multipart.build_multipart(
        "csrf_token" => "test-token", "image" => upload, "width" => "2", "height" => "2",
        "pixel_size" => "1", "brightness" => "10", "separate_z_parts" => "1"
      )

      response = request.post(
        "/jobs", "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => multipart_content_type, input: body
      )

      expect(response.status).to eq(303)
      expect(response["location"]).to end_with("/?job=web-job")
      expect(launcher.request.fetch(:filename)).to eq("input.png")
      expect(launcher.request.fetch(:settings)).to have_attributes(
        width: 2.0, height: 2.0, pixel_size: 1.0, brightness: 10.0, separate_z_parts: true
      )
    ensure
      input&.close!
    end
  end

  it "starts a conversion asynchronously and returns its job location" do
    Dir.mktmpdir do |project_dir|
      request, launcher = request_for(project_dir)
      input = Tempfile.new(["input", ".png"])
      input.write("image")
      input.close
      upload = Rack::Multipart::UploadedFile.new(input.path, "image/png", filename: "input.png")
      body = Rack::Multipart.build_multipart(
        "csrf_token" => "test-token", "image" => upload, "width" => "2", "height" => "2", "pixel_size" => "1"
      )

      response = request.post(
        "/jobs", "HTTP_HOST" => "127.0.0.1", "HTTP_ACCEPT" => "application/json",
                 "CONTENT_TYPE" => multipart_content_type, input: body
      )

      expect(response.status).to eq(202)
      expect(JSON.parse(response.body)).to eq("job_id" => "web-job", "url" => "/?job=web-job")
      expect(launcher.request.fetch(:filename)).to eq("input.png")
    ensure
      input&.close!
    end
  end

  it "lists recent jobs for asynchronous history updates" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p(jobs)
      File.write(
        File.join(jobs, "recent.json"),
        JSON.generate(job_id: "recent", state: "completed", phase: "completed", percent: 100, files: [])
      )
      request, = request_for(project_dir)

      response = request.get("/api/jobs?limit=6", "HTTP_HOST" => "127.0.0.1")

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body).fetch("jobs").first).to include("job_id" => "recent", "state" => "completed")
    end
  end

  it "returns persisted status and only its recorded artifacts" do
    Dir.mktmpdir do |project_dir|
      output = File.join(project_dir, "build", "job-1")
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p([output, jobs])
      File.binwrite(File.join(output, "preview.png"), "preview")
      File.binwrite(File.join(output, "corrected-input.png"), "corrected")
      File.write(File.join(jobs, "job-1.log"), "conversion log\n")
      File.write(
        File.join(jobs, "job-1.json"),
        JSON.generate(
          job_id: "job-1", state: "completed", phase: "completed", percent: 100,
          message: "Conversion completed", output_path: output,
          files: ["corrected-input.png", "preview.png"]
        )
      )
      request, = request_for(project_dir)

      status = request.get("/api/jobs/job-1", "HTTP_HOST" => "127.0.0.1")
      artifact = request.get("/jobs/job-1/files/preview.png", "HTTP_HOST" => "127.0.0.1")
      corrected = request.get("/jobs/job-1/files/corrected-input.png", "HTTP_HOST" => "127.0.0.1")
      missing = request.get("/jobs/job-1/files/settings.json", "HTTP_HOST" => "127.0.0.1")
      log = request.get("/jobs/job-1/log", "HTTP_HOST" => "127.0.0.1")

      expect(JSON.parse(status.body)).to include(
        "state" => "completed", "preview_url" => "/jobs/job-1/files/preview.png",
        "corrected_input_url" => "/jobs/job-1/files/corrected-input.png",
        "log_url" => "/jobs/job-1/log",
        "file_count" => 2, "size_bytes" => 16
      )
      expect(artifact).to have_attributes(status: 200, body: "preview")
      expect(corrected).to have_attributes(status: 200, body: "corrected")
      expect(missing.status).to eq(404)
      expect(log).to have_attributes(status: 200, body: "conversion log\n")
    end
  end

  it "opens only a recorded completed 3MF in Bambu Studio" do
    Dir.mktmpdir do |project_dir|
      output = File.join(project_dir, "build", "model-job")
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p([output, jobs])
      model = File.join(output, "lithop.3mf")
      File.write(model, "model")
      File.write(
        File.join(jobs, "model-job.json"),
        JSON.generate(
          job_id: "model-job", state: "completed", output_path: output, files: ["lithop.3mf"]
        )
      )
      request, _, bambu_studio_launcher = request_for(project_dir)

      headers = {
        "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded", input: "name=lithop.3mf"
      }
      response = request.post("/api/jobs/model-job/open-in-bambu-studio", headers)

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to eq(
        "status" => "launch_requested", "job_id" => "model-job", "name" => "lithop.3mf"
      )
      expect(bambu_studio_launcher.opened).to eq(job_id: "model-job", path: File.realpath(model))
    end
  end

  it "rejects invalid, missing, and unfinished Bambu Studio open requests" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p(jobs)
      File.write(File.join(jobs, "running.json"), JSON.generate(job_id: "running", state: "running", files: []))
      request, = request_for(project_dir)
      headers = {
        "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded"
      }

      invalid = request.post(
        "/api/jobs/running/open-in-bambu-studio", headers.merge(input: "name=../outside.3mf")
      )
      wrong_type = request.post(
        "/api/jobs/running/open-in-bambu-studio", headers.merge(input: "name=model.stl")
      )
      unfinished = request.post(
        "/api/jobs/running/open-in-bambu-studio", headers.merge(input: "name=lithop.3mf")
      )
      missing = request.post(
        "/api/jobs/missing/open-in-bambu-studio", headers.merge(input: "name=lithop.3mf")
      )

      expect(invalid.status).to eq(422)
      expect(wrong_type.status).to eq(422)
      expect(unfinished.status).to eq(409)
      expect(missing.status).to eq(404)
    end
  end

  it "reports a Bambu Studio launch failure without removing the model" do
    Dir.mktmpdir do |project_dir|
      output = File.join(project_dir, "build", "model-job")
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p([output, jobs])
      model = File.join(output, "lithop.3mf")
      File.write(model, "model")
      File.write(
        File.join(jobs, "model-job.json"),
        JSON.generate(job_id: "model-job", state: "completed", output_path: output, files: ["lithop.3mf"])
      )
      unavailable = Class.new do
        def supported? = true
        def active?(_job_id) = false
        def open(**) = raise Lithop::Web::BambuStudioLauncher::UnavailableError, "Bambu Studio is unavailable"
      end.new
      request, = request_for(project_dir, bambu_studio_launcher: unavailable)

      headers = {
        "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded", input: "name=lithop.3mf"
      }
      response = request.post("/api/jobs/model-job/open-in-bambu-studio", headers)

      expect(response.status).to eq(503)
      expect(JSON.parse(response.body)).to eq("error" => "Bambu Studio is unavailable")
      expect(File).to exist(model)
    end
  end

  it "presents recorded tile coordinates and Z plate structure from the manifest" do
    Dir.mktmpdir do |project_dir|
      output = File.join(project_dir, "build", "tiles-job")
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p([File.join(output, "tiles"), jobs])
      File.write(File.join(output, "tiles", "tile_r01_c01.3mf"), "model")
      manifest = {
        tile_layout: { tile_count: 2, rows: 1, columns: 2 },
        tiles: [
          {
            id: "tile_r01_c01", file: "tiles/tile_r01_c01.3mf", row: 1, column: 1,
            offset_mm: { x: 0.0, y: 0.0 }, dimensions_mm: { width: 70.0, height: 104.0 }
          }
        ],
        color_model: { z_part_separation: { enabled: true, color_regions: [{ id: "color_region_1" }] } }
      }
      File.write(File.join(output, "manifest.json"), JSON.generate(manifest))
      files = ["manifest.json", "tiles/tile_r01_c01.3mf"]
      File.write(
        File.join(jobs, "tiles-job.json"),
        JSON.generate(
          job_id: "tiles-job", state: "completed", phase: "completed", percent: 100,
          output_path: output, files:
        )
      )
      request, = request_for(project_dir)

      response = request.get("/api/jobs/tiles-job", "HTTP_HOST" => "127.0.0.1")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload.fetch("tile_layout_metadata")).to include("rows" => 1, "columns" => 2)
      expect(payload.fetch("tiles").first).to include("id" => "tile_r01_c01", "row" => 1, "column" => 1)
      expect(payload.fetch("z_part_separation")).to include("enabled" => true)
    end
  end

  it "validates and renders SVG as a bounded PNG before conversion" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)
      input = Tempfile.new(["input", ".svg"])
      input.write(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 1">' \
        '<rect width="2" height="1" fill="#0086D6"/></svg>'
      )
      input.close
      upload = Rack::Multipart::UploadedFile.new(input.path, "image/svg+xml", filename: "input.svg")
      body = Rack::Multipart.build_multipart("csrf_token" => "test-token", "image" => upload)

      staged = request.post(
        "/api/previews", "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => multipart_content_type, input: body
      )
      preview_id = JSON.parse(staged.body).fetch("id")
      rendered = request.post(
        "/api/previews/#{preview_id}/render",
        "HTTP_HOST" => "127.0.0.1",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        input: "csrf_token=test-token&width=140&height=104&pixel_size=0.22"
      )

      expect(staged.status).to eq(200)
      expect(rendered.status).to eq(200)
      expect(rendered["content-type"]).to start_with("image/png")
      expect(rendered["x-lithop-preview-cache"]).to eq("miss")
      expect(rendered["server-timing"]).to match(/preview;dur=/)
      expect(rendered.body).to start_with("\x89PNG\r\n\x1A\n".b)
    ensure
      input&.close!
    end
  end

  it "renders a transparent tile overlay from the common layout" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)

      response = request.post(
        "/api/tile-layout", "HTTP_HOST" => "127.0.0.1",
                            "CONTENT_TYPE" => "application/x-www-form-urlencoded",
                            input: "csrf_token=test-token&width=20&height=10&pixel_size=1&" \
                                   "tile_count=2&tile_layout=columns"
      )

      expect(response.status).to eq(200)
      expect(response["content-type"]).to start_with("image/svg+xml")
      expect(response.body).to include('fill="none"', "tile_r01_c01", "tile_r01_c02")
    end
  end

  it "returns the resolved tile and Z plate counts for the draft summary" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)

      response = request.post(
        "/api/settings-summary", "HTTP_HOST" => "127.0.0.1",
                                 "CONTENT_TYPE" => "application/x-www-form-urlencoded",
                                 input: "csrf_token=test-token&width=140&height=104&pixel_size=1&" \
                                        "tile_count=6&tile_layout=grid&tile_rows=2&tile_columns=3&" \
                                        "separate_z_parts=1&color_region_parts=3"
      )

      expect(response.status).to eq(200)
      expect(JSON.parse(response.body)).to eq(
        "tile_count" => 6, "tile_rows" => 2, "tile_columns" => 3, "z_plate_count" => 4
      )
    end
  end

  it "starts a job from a staged preview and removes the temporary input" do
    Dir.mktmpdir do |project_dir|
      request, launcher = request_for(project_dir)
      input = Tempfile.new(["input", ".png"])
      input.write("staged-image")
      input.close
      upload = Rack::Multipart::UploadedFile.new(input.path, "image/png", filename: "input.png")
      body = Rack::Multipart.build_multipart("csrf_token" => "test-token", "image" => upload)
      staged = request.post(
        "/api/previews", "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => multipart_content_type, input: body
      )
      preview_id = JSON.parse(staged.body).fetch("id")

      response = request.post(
        "/jobs",
        "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        input: "csrf_token=test-token&preview_id=#{preview_id}&width=2&height=2&pixel_size=1"
      )

      expect(response.status).to eq(303)
      expect(launcher.request).to include(filename: "input.png", contents: "staged-image")
      expect(Dir).not_to exist(File.join(project_dir, "build", ".previews", preview_id))
    ensure
      input&.close!
    end
  end

  it "removes a staged preview when submitted settings are invalid" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)
      input = Tempfile.new(["input", ".png"])
      input.write("staged-image")
      input.close
      upload = Rack::Multipart::UploadedFile.new(input.path, "image/png", filename: "input.png")
      body = Rack::Multipart.build_multipart("csrf_token" => "test-token", "image" => upload)
      staged = request.post(
        "/api/previews", "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => multipart_content_type, input: body
      )
      preview_id = JSON.parse(staged.body).fetch("id")

      response = request.post(
        "/jobs",
        "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        input: "csrf_token=test-token&preview_id=#{preview_id}&width=invalid"
      )

      expect(response.status).to eq(422)
      expect(Dir).not_to exist(File.join(project_dir, "build", ".previews", preview_id))
    ensure
      input&.close!
    end
  end

  it "delegates stopping to the launcher and deletes only final jobs" do
    Dir.mktmpdir do |project_dir|
      request, launcher = request_for(project_dir)
      jobs = File.join(project_dir, "build", ".jobs")
      output = File.join(project_dir, "build", "done")
      FileUtils.mkdir_p([jobs, output])
      File.write(File.join(output, "preview.png"), "preview")
      File.write(File.join(jobs, "active.json"), JSON.generate(job_id: "active", state: "running"))
      File.write(
        File.join(jobs, "done.json"),
        JSON.generate(job_id: "done", state: "completed", output_path: output, files: ["preview.png"])
      )

      stopped = request.post(
        "/jobs/active/cancel", "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token"
      )
      deleted = request.post(
        "/jobs/done/delete", "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token"
      )

      expect(stopped.status).to eq(200)
      expect(launcher.cancelled).to eq("active")
      expect(JSON.parse(deleted.body)).to include("ok" => true, "file_count" => 1, "size_bytes" => 7)
      expect(Dir).not_to exist(output)
      expect(File).to exist(File.join(jobs, "active.json"))
    end
  end

  it "saves UI-only settings and restores them through the versioned library API" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)
      request_headers = {
        "HTTP_HOST" => "127.0.0.1", "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        input: "csrf_token=test-token&name=fine-line&width=120&height=90&brightness=5"
      }

      saved = request.post("/api/settings-library/presets", request_headers)
      restored = request.get("/api/settings-library", "HTTP_HOST" => "127.0.0.1")

      expect(saved.status).to eq(200)
      expect(JSON.parse(restored.body).dig("presets", "fine-line", "settings")).to include(
        "width" => 120.0, "height" => 90.0, "brightness" => 5.0
      )
      expect(File).not_to exist(File.join(project_dir, "config", "settings.json"))
    end
  end

  it "filters the full job history and reports page metadata" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p(jobs)
      %w[alpha beta gamma].each_with_index do |name, index|
        id = "job-#{index}"
        File.write(File.join(jobs, "#{id}.json"), JSON.generate(job_id: id, state: "completed", files: []))
        File.write(File.join(jobs, "#{id}.request.json"), JSON.generate(input_name: "#{name}.png"))
      end
      request, = request_for(project_dir)

      response = request.get("/api/jobs?limit=1&offset=0&q=beta&state=completed", "HTTP_HOST" => "127.0.0.1")
      payload = JSON.parse(response.body)

      expect(response.status).to eq(200)
      expect(payload).to include("total" => 1, "offset" => 0, "limit" => 1)
      expect(payload.fetch("jobs").first).to include("input_name" => "beta.png")
    end
  end

  it "previews archives, downloads a ZIP, and bulk-deletes final jobs" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      %w[first second].each do |id|
        output = File.join(project_dir, "build", id)
        FileUtils.mkdir_p([jobs, output])
        File.write(File.join(output, "#{id}.3mf"), id)
        File.write(
          File.join(jobs, "#{id}.json"),
          JSON.generate(job_id: id, state: "completed", output_path: output, files: ["#{id}.3mf"])
        )
      end
      request, = request_for(project_dir)
      delete_headers = {
        "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token",
        "CONTENT_TYPE" => "application/x-www-form-urlencoded",
        input: "job_ids%5B%5D=first&job_ids%5B%5D=second"
      }

      summary = request.get("/api/jobs/first/archive-summary?scope=models", "HTTP_HOST" => "127.0.0.1")
      archive = request.get("/jobs/first/archive?scope=models", "HTTP_HOST" => "127.0.0.1")
      deleted = request.post("/api/jobs/delete", delete_headers)

      expect(JSON.parse(summary.body)).to include("file_count" => 1, "size_bytes" => 5)
      expect(archive.status).to eq(200)
      expect(archive["content-type"]).to start_with("application/zip")
      expect(Dir.glob(File.join(project_dir, "build", ".downloads", "*.zip"))).to be_empty
      expect(JSON.parse(deleted.body)).to include("ok" => true)
      expect(JSON.parse(deleted.body).fetch("deleted").map { |entry| entry.fetch("job_id") }).to contain_exactly(
        "first", "second"
      )
    end
  end

  it "rejects state-changing requests without its page token" do
    Dir.mktmpdir do |project_dir|
      request, = request_for(project_dir)

      response = request.post("/jobs", "HTTP_HOST" => "127.0.0.1")

      expect(response.status).to eq(403)
    end
  end

  it "does not add cancellation requests to completed jobs" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      FileUtils.mkdir_p(jobs)
      File.write(
        File.join(jobs, "done.json"),
        JSON.generate(job_id: "done", state: "completed", phase: "completed", percent: 100, files: [])
      )
      request, = request_for(project_dir)

      response = request.post(
        "/jobs/done/cancel", "HTTP_HOST" => "127.0.0.1", "HTTP_X_CSRF_TOKEN" => "test-token"
      )

      expect(response.status).to eq(422)
      expect(File).not_to exist(File.join(jobs, "done.cancel"))
    end
  end

  def multipart_content_type
    "multipart/form-data; boundary=#{Rack::Multipart::MULTIPART_BOUNDARY}"
  end
end

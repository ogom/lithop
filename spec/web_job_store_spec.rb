# frozen_string_literal: true

require "json"
require "zip"
require "lithop/web/job_store"

RSpec.describe Lithop::Web::JobStore do
  def write_job(project_dir, job_id, state:, output: false)
    jobs = File.join(project_dir, "build", ".jobs")
    path = File.join(project_dir, "build", job_id)
    FileUtils.mkdir_p(jobs)
    if output
      FileUtils.mkdir_p(path)
      File.write(File.join(path, "preview.png"), "12345")
    end
    File.write(
      File.join(jobs, "#{job_id}.json"),
      JSON.generate(job_id:, state:, output_path: output ? path : nil, files: output ? ["preview.png"] : nil)
    )
  end

  it "reports and deletes one final job without touching another job" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "delete-me", state: "completed", output: true)
      write_job(project_dir, "keep-me", state: "completed", output: true)
      store = described_class.new(project_dir:)

      expect(store.summary("delete-me")).to eq("file_count" => 1, "size_bytes" => 5)
      expect(store.delete("delete-me")).to eq("file_count" => 1, "size_bytes" => 5)
      expect(store.fetch("delete-me")).to be_nil
      expect(store.fetch("keep-me")).to include("state" => "completed")
      expect(Dir).to exist(File.join(project_dir, "build", "keep-me"))
    end
  end

  it "merges UI request metadata without listing its sidecar as a job" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "described", state: "completed", output: true)
      jobs = File.join(project_dir, "build", ".jobs")
      File.write(
        File.join(jobs, "described.request.json"),
        JSON.generate(input_name: "chart.svg", width: 140.0, height: 104.0, tile_count: 2)
      )
      store = described_class.new(project_dir:)

      expect(store.fetch("described")).to include(
        "input_name" => "chart.svg", "width" => 140.0, "height" => 104.0, "tile_count" => 2
      )
      expect(store.recent.map { |job| job.fetch("job_id") }).to eq(["described"])
      store.delete("described")
      expect(File).not_to exist(File.join(jobs, "described.request.json"))
    end
  end

  it "places active conversions before final history entries" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "20261017T020000Z-done", state: "completed", output: true)
      write_job(project_dir, "20261017T010000Z-active", state: "running")
      store = described_class.new(project_dir:)

      expect(store.recent.map { |job| job.fetch("state") }).to eq(%w[running completed])
    end
  end

  it "searches and pages the full history before returning results" do
    Dir.mktmpdir do |project_dir|
      15.times do |index|
        id = format("job-%02d", index)
        write_job(project_dir, id, state: "completed", output: true)
        jobs = File.join(project_dir, "build", ".jobs")
        File.write(File.join(jobs, "#{id}.request.json"), JSON.generate(input_name: "photo-#{index}.png"))
      end
      store = described_class.new(project_dir:)

      page = store.page(
        limit: 5, offset: 5, filters: { query: "photo", state: "completed", sort: "name_asc" }
      )

      expect(page).to include("total" => 15, "offset" => 5, "limit" => 5)
      expect(page.fetch("jobs").map { |job| job.fetch("input_name") }).to eq(
        %w[photo-13.png photo-14.png photo-2.png photo-3.png photo-4.png]
      )
    end
  end

  it "archives only published model files or every published artifact" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "archive", state: "completed", output: true)
      output = File.join(project_dir, "build", "archive")
      File.write(File.join(output, "lithop.3mf"), "model")
      File.write(File.join(output, "settings.json"), "settings")
      jobs = File.join(project_dir, "build", ".jobs")
      File.write(
        File.join(jobs, "archive.json"),
        JSON.generate(job_id: "archive", state: "completed", output_path: output,
                      files: ["preview.png", "lithop.3mf", "settings.json"])
      )
      store = described_class.new(project_dir:)

      expect(store.archive_summary("archive", scope: "models")).to include("file_count" => 1, "size_bytes" => 5)
      path = store.create_archive("archive", scope: "all")
      Zip::File.open(path) do |archive|
        expect(archive.entries.map(&:name)).to contain_exactly("preview.png", "lithop.3mf", "settings.json")
      end
      described_class.new(project_dir:)
      expect(File).not_to exist(path)
    end
  end

  it "does not follow a symbolic archive directory" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "archive", state: "completed", output: true)
      outside = Dir.mktmpdir
      File.write(File.join(outside, "keep.zip"), "outside")
      File.symlink(outside, File.join(project_dir, "build", ".downloads"))
      store = described_class.new(project_dir:)

      expect(File).to exist(File.join(outside, "keep.zip"))
      expect { store.create_archive("archive", scope: "all") }.to raise_error(
        Lithop::InputError, /must not be a symbolic link/
      )
    ensure
      FileUtils.rm_rf(outside) if outside
    end
  end

  it "refuses active jobs and symbolic output directories" do
    Dir.mktmpdir do |project_dir|
      write_job(project_dir, "active", state: "running")
      write_job(project_dir, "linked", state: "failed")
      outside = Dir.mktmpdir
      File.symlink(outside, File.join(project_dir, "build", "linked"))
      store = described_class.new(project_dir:)

      expect { store.delete("active") }.to raise_error(Lithop::InputError, /must be stopped/)
      expect { store.delete("linked") }.to raise_error(Lithop::InputError, /symbolic/)
      expect(Dir).to exist(outside)
    ensure
      FileUtils.rm_rf(outside) if outside
    end
  end
end

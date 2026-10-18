# frozen_string_literal: true

require "json"
require "tempfile"
require "timeout"
require "vips"
require "lithop/web/job_launcher"

RSpec.describe Lithop::Web::JobLauncher do
  it "runs the shared exporter in a child process and removes the staged upload" do
    Dir.mktmpdir do |project_dir|
      input = Tempfile.new(["input", ".png"])
      Vips::Image.black(2, 2).pngsave(input.path)
      clock = instance_double("Clock", now: Time.utc(2026, 10, 17, 1, 2, 3))
      random = instance_double("Random", hex: "12345678")
      settings = Lithop::Settings.new(
        width: 2.0, height: 2.0, pixel_size: 1.0, grid_columns: nil, grid_rows: nil
      )
      launcher = described_class.new(project_dir:, clock:, random:)

      job_id = launcher.start(upload: input, filename: "input.png", settings:)
      status_path = File.join(project_dir, "build", ".jobs", "#{job_id}.json")
      status = wait_for_terminal_status(status_path)

      expect(status).to include("state" => "completed", "percent" => 100.0)
      expect(File).to exist(File.join(status.fetch("output_path"), "preview.png"))
      request = JSON.parse(File.read(File.join(project_dir, "build", ".jobs", "#{job_id}.request.json")))
      expect(request).to include(
        "input_name" => "input.png", "width" => 2.0, "height" => 2.0, "tile_count" => 1
      )
      wait_for_removal(File.join(project_dir, "build", ".web", job_id))
    ensure
      input&.close!
    end
  end

  it "escalates cancellation only for the child process group it owns" do
    Dir.mktmpdir do |project_dir|
      input = StringIO.new("image")
      waits = Queue.new
      signals = Queue.new
      process = Object.new
      process.define_singleton_method(:spawn) { |*_args, **_options| 4321 }
      process.define_singleton_method(:wait) { |_pid| waits.pop }
      process.define_singleton_method(:getpgid) { |pid| pid }
      process.define_singleton_method(:kill) { |signal, pid| signals << [signal, pid] }
      launcher = described_class.new(
        project_dir:, process:, sleeper: ->(_seconds) {},
        clock: instance_double("Clock", now: Time.utc(2026, 10, 17, 1, 2, 3)),
        random: instance_double("Random", hex: "12345678")
      )
      settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0)

      job_id = launcher.start(upload: input, filename: "input.png", settings:)
      launcher.cancel(job_id)
      delivered = Timeout.timeout(2) { [signals.pop, signals.pop] }

      expect(delivered).to eq([["TERM", -4321], ["KILL", -4321]])
      waits << true
      wait_for_removal(File.join(project_dir, "build", ".web", job_id))
    end
  end

  it "reconciles an abandoned temporary conversion when the UI restarts" do
    Dir.mktmpdir do |project_dir|
      build = File.join(project_dir, "build")
      jobs = File.join(build, ".jobs")
      temporary = File.join(build, ".tmp-stale-ui-job")
      FileUtils.mkdir_p([jobs, temporary])
      File.write(
        File.join(temporary, Lithop::JobDirectory::OWNER_FILE),
        JSON.generate(job_id: "stale-ui-job", pid: 999_999_999, created_at: Time.now.utc.iso8601)
      )
      File.write(
        File.join(jobs, "stale-ui-job.json"),
        JSON.generate(job_id: "stale-ui-job", state: "running", phase: "mesh", percent: 40)
      )

      described_class.new(project_dir:)
      record = JSON.parse(File.read(File.join(jobs, "stale-ui-job.json")))

      expect(record).to include("state" => "failed", "phase" => "failed")
      expect(Dir).not_to exist(temporary)
    end
  end

  def wait_for_terminal_status(path)
    Timeout.timeout(10) do
      loop do
        if File.file?(path)
          record = JSON.parse(File.read(path))
          return record if Lithop::JobExecution::FINAL_STATES.include?(record["state"])
        end
        sleep 0.02
      end
    end
  end

  def wait_for_removal(path)
    Timeout.timeout(2) do
      sleep 0.01 while File.exist?(path)
    end
  end
end

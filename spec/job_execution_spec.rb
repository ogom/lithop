# frozen_string_literal: true

require "json"

RSpec.describe Lithop::JobExecution do
  let(:result_class) { Data.define(:path, :files) }

  def read_status(execution)
    JSON.parse(File.read(execution.status_path))
  end

  it "records progress and a completed result" do
    Dir.mktmpdir do |project_dir|
      events = []
      execution = described_class.new(project_dir:, job_id: "job-1", progress: events.method(:<<))
      output_path = File.join(project_dir, "build", "job-1")

      result = execution.call do |job|
        job.progress(phase: :mesh, percent: 45, message: "Building mesh")
        result_class.new(path: output_path, files: ["lithop.3mf"])
      end

      status = read_status(execution)
      expect(result.path).to eq(output_path)
      expect(status).to include(
        "state" => "completed", "phase" => "completed", "percent" => 100.0,
        "output_path" => output_path, "files" => ["lithop.3mf"], "error" => nil
      )
      expect(events.map(&:state)).to include("queued", "running", "completed")
      expect(events).to include(have_attributes(phase: "mesh", percent: 45.0))
    end
  end

  it "records failure without reporting the job as complete" do
    Dir.mktmpdir do |project_dir|
      execution = described_class.new(project_dir:, job_id: "job-failed")

      expect { execution.call { raise "write failed" } }.to raise_error(RuntimeError, "write failed")

      status = read_status(execution)
      expect(status).to include("state" => "failed", "phase" => "failed", "finished_at" => be_a(String))
      expect(status.dig("error", "message")).to eq("write failed")
      expect(status.fetch("output_path")).to be_nil
    end
  end

  it "limits a project to one active conversion" do
    Dir.mktmpdir do |project_dir|
      entered = Queue.new
      release = Queue.new
      first = described_class.new(project_dir:, job_id: "job-first")
      second = described_class.new(project_dir:, job_id: "job-second")
      thread = Thread.new do
        first.call do
          entered << true
          release.pop
          :done
        end
      end
      entered.pop

      expect { second.call { :not_reached } }
        .to raise_error(Lithop::Error, /another conversion is already running/)
      expect(read_status(second).fetch("state")).to eq("failed")
      release << true
      expect(thread.value).to eq(:done)
      expect(read_status(first).fetch("state")).to eq("completed")
    end
  end

  it "records a cancellation requested during conversion" do
    Dir.mktmpdir do |project_dir|
      execution = described_class.new(project_dir:, job_id: "job-cancelled")

      expect do
        execution.call do |job|
          described_class.request_cancel(project_dir:, job_id: job.job_id)
          job.progress(phase: :mesh, percent: 50, message: "Building mesh")
        end
      end.to raise_error(Lithop::JobCancelled)

      status = read_status(execution)
      expect(status).to include("state" => "cancelled", "phase" => "cancelled", "finished_at" => be_a(String))
      expect(File).not_to exist(File.join(project_dir, "build", ".jobs", "job-cancelled.cancel"))
    end
  end

  it "keeps a published result completed when cancellation arrives after the commit point" do
    Dir.mktmpdir do |project_dir|
      execution = described_class.new(project_dir:, job_id: "job-published")
      output_path = File.join(project_dir, "build", "job-published")

      execution.call do |job|
        FileUtils.mkdir_p(output_path)
        File.write(File.join(output_path, "preview.png"), "published")
        job.publication_committed!
        described_class.request_cancel(project_dir:, job_id: job.job_id)
        result_class.new(path: output_path, files: ["preview.png"])
      end

      expect(read_status(execution)).to include(
        "state" => "completed", "output_path" => output_path, "files" => ["preview.png"]
      )
    end
  end

  it "serializes cancellation against the publication checkpoint" do
    Dir.mktmpdir do |project_dir|
      execution = described_class.new(project_dir:, job_id: "job-boundary")
      checkpoint = Queue.new
      publish = Queue.new
      cancel_started = Queue.new
      output_path = File.join(project_dir, "build", "job-boundary")
      execution_thread = Thread.new do
        execution.call do |job|
          job.checkpoint!
          checkpoint << true
          publish.pop
          FileUtils.mkdir_p(output_path)
          job.publication_committed!
          result_class.new(path: output_path, files: [])
        end
      end
      checkpoint.pop
      cancel_thread = Thread.new do
        cancel_started << true
        described_class.request_cancel(project_dir:, job_id: "job-boundary")
      end
      cancel_started.pop
      sleep 0.02

      expect(cancel_thread).to be_alive
      expect(File).not_to exist(File.join(project_dir, "build", ".jobs", "job-boundary.cancel"))
      publish << true
      execution_thread.value
      cancel_thread.join
      expect(read_status(execution)).to include("state" => "completed")
      expect(File).not_to exist(File.join(project_dir, "build", ".jobs", "job-boundary.cancel"))
    end
  end

  it "reconciles an externally stopped active process to its persisted output" do
    Dir.mktmpdir do |project_dir|
      jobs = File.join(project_dir, "build", ".jobs")
      output = File.join(project_dir, "build", "job-exited")
      FileUtils.mkdir_p([jobs, output])
      File.write(File.join(output, "preview.png"), "preview")
      File.write(
        File.join(jobs, "job-exited.json"),
        JSON.generate(job_id: "job-exited", state: "cancelling", phase: "cancelling", percent: 95)
      )

      record = described_class.finalize_process_exit(project_dir:, job_id: "job-exited")

      expect(record).to include(
        "state" => "completed", "output_path" => output, "files" => ["preview.png"]
      )
    end
  end

  it "records cancellation when a child exits before creating its first status" do
    Dir.mktmpdir do |project_dir|
      described_class.request_cancel(project_dir:, job_id: "job-early")

      record = described_class.finalize_process_exit(project_dir:, job_id: "job-early")

      expect(record).to include("state" => "cancelled", "phase" => "cancelled", "percent" => 0)
      expect(JSON.parse(File.read(File.join(project_dir, "build", ".jobs", "job-early.json"))))
        .to include("state" => "cancelled")
      expect(File).not_to exist(File.join(project_dir, "build", ".jobs", "job-early.cancel"))
    end
  end

  it "recovers stale owned data and changes its active state to failed" do
    Dir.mktmpdir do |project_dir|
      build_dir = File.join(project_dir, "build")
      jobs_dir = File.join(build_dir, ".jobs")
      temporary = File.join(build_dir, ".tmp-abandoned")
      FileUtils.mkdir_p([jobs_dir, temporary])
      File.write(
        File.join(temporary, Lithop::JobDirectory::OWNER_FILE),
        JSON.generate(job_id: "abandoned", pid: 999_999_999, created_at: Time.now.utc.iso8601)
      )
      File.write(
        File.join(jobs_dir, "abandoned.json"),
        JSON.generate(job_id: "abandoned", state: "running", percent: 40)
      )

      described_class.new(project_dir:, job_id: "replacement").call { :done }

      recovered = JSON.parse(File.read(File.join(jobs_dir, "abandoned.json")))
      expect(recovered).to include("state" => "failed", "phase" => "recovered")
      expect(Dir).not_to exist(temporary)
    end
  end

  it "does not overwrite an existing job state with the same ID" do
    Dir.mktmpdir do |project_dir|
      first = described_class.new(project_dir:, job_id: "same-job")
      first.call { :done }
      original = File.read(first.status_path)

      expect { described_class.new(project_dir:, job_id: "same-job").call { :not_reached } }
        .to raise_error(Lithop::Error, /job state already exists/)
      expect(File.read(first.status_path)).to eq(original)
    end
  end
end

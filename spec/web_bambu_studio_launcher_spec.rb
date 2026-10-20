# frozen_string_literal: true

require "tempfile"
require "lithop"
require "lithop/web/bambu_studio_launcher"

RSpec.describe Lithop::Web::BambuStudioLauncher do
  it "passes a validated 3MF to the fixed Bambu Studio bundle without a shell" do
    model = Tempfile.new(["lithop model 日本語", ".3mf"])
    calls = []
    runner = lambda do |command, timeout|
      calls << [command, timeout]
      true
    end
    launcher = described_class.new(platform: "arm64-darwin", runner:)

    expect(launcher.open(job_id: "job-1", path: model.path)).to be(true)
    expect(calls).to eq(
      [[["/usr/bin/open", "-b", "com.bambulab.bambu-studio", model.path], 5]]
    )
  ensure
    model&.close!
  end

  it "rejects unsupported platforms and non-3MF files before launching" do
    model = Tempfile.new(["lithop", ".stl"])
    runner = spy("runner")

    expect do
      described_class.new(platform: "linux", runner:).open(job_id: "job-1", path: model.path)
    end.to raise_error(described_class::UnsupportedPlatformError)
    expect do
      described_class.new(platform: "darwin", runner:).open(job_id: "job-1", path: model.path)
    end.to raise_error(described_class::InvalidArtifactError, "artifact must be a 3MF file")
    expect(runner).not_to have_received(:call)
  ensure
    model&.close!
  end

  it "prevents a second launch while the first request is active" do
    model = Tempfile.new(["lithop", ".3mf"])
    started = Queue.new
    release = Queue.new
    runner = lambda do |_command, _timeout|
      started << true
      release.pop
      true
    end
    launcher = described_class.new(platform: "darwin", runner:)
    first = Thread.new { launcher.open(job_id: "job-1", path: model.path) }
    started.pop

    expect(launcher).to be_active("job-1")
    expect { launcher.open(job_id: "job-2", path: model.path) }.to raise_error(described_class::BusyError)

    release << true
    expect(first.value).to be(true)
    expect(launcher).not_to be_active("job-1")
  ensure
    release << true if release && release.empty?
    first&.join
    model&.close!
  end
end

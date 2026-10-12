# frozen_string_literal: true

RSpec.describe Lithop::Calibration::Export do
  let(:clock) { instance_double("Clock", now: Time.utc(2026, 10, 6)) }
  let(:random) { instance_double("Random", hex: "12345678") }
  let(:settings) { Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0) }

  it "preserves a colliding temporary job owned by another run" do
    Dir.mktmpdir do |directory|
      job_id = "20261006T000000Z-12345678-calibration"
      temporary = File.join(directory, "build", ".tmp-#{job_id}")
      FileUtils.mkdir_p(temporary)
      sentinel = File.join(temporary, "owner.txt")
      File.write(sentinel, "keep")
      exporter = described_class.new(settings:, project_dir: directory, clock:, random:)

      expect { exporter.call }.to raise_error(Lithop::Error, /output already exists/)
      expect(File.read(sentinel)).to eq("keep")
    end
  end

  it "removes only its own temporary job after an interruption" do
    Dir.mktmpdir do |directory|
      job_id = "20261006T000000Z-12345678-calibration"
      temporary = File.join(directory, "build", ".tmp-#{job_id}")
      exporter = described_class.new(settings:, project_dir: directory, clock:, random:)
      allow(Lithop::ThreeMF).to receive(:write).and_raise(Interrupt)

      expect { exporter.call }.to raise_error(Interrupt)
      expect(Dir).not_to exist(temporary)
    end
  end
end

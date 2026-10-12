# frozen_string_literal: true

require "json"

RSpec.describe Lithop::Calibration::Profile do
  let(:settings) { Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0) }
  let(:target) { Lithop::Calibration::Target.new(settings:) }

  it "round-trips a draft measurement profile" do
    profile = described_class.template(profile_id: "cal-001", settings:, target:)

    Dir.mktmpdir do |directory|
      path = File.join(directory, "profile.json")
      profile.write(path)
      loaded = described_class.load(path)

      expect(loaded.data.fetch("profile_id")).to eq("cal-001")
      expect(loaded.data.fetch("patches").length).to eq(128)
      expect(loaded.validate_for!(settings)).to be(true)
    end
  end

  it "rejects a profile for a different layer structure" do
    profile = described_class.template(profile_id: "cal-001", settings:, target:)
    other = Lithop::Settings.new(
      width: 2.0,
      height: 2.0,
      pixel_size: 1.0,
      minimum_thickness: 0.99,
      color_layer_count: 4
    )

    expect { profile.validate_for!(other) }
      .to raise_error(Lithop::ConfigurationError, /does not match/)
  end

  it "validates measurement values when reading a profile" do
    profile = described_class.template(profile_id: "cal-001", settings:, target:)
    profile.data.fetch("patches").first.fetch("measurements") << {
      "transmitted_srgb" => [0.9, 0.8, 0.7],
      "luminance" => 120.5
    }

    expect { described_class.new(profile.data) }.not_to raise_error

    profile.data.fetch("patches").first.fetch("measurements").first["luminance"] = -1
    expect { described_class.new(profile.data) }
      .to raise_error(Lithop::InputError, /non-negative luminance/)
  end

  it "averages repeated measurements from a complete measured profile" do
    profile = measured_calibration_profile(settings) do |candidate|
      candidate.data.fetch("patches").first.fetch("measurements") << {
        "transmitted_srgb" => [0.8, 0.6, 0.4],
        "luminance" => 80.0
      }
    end

    expect(profile.validate_complete!).to be(true)
    first = profile.measurements(:recipe).first
    expect(first.transmitted_srgb).to eq([0.9, 0.8, 0.7])
    expect(first.luminance).to eq(90.0)
  end

  it "rejects a draft profile with unmeasured patches and references" do
    profile = described_class.template(profile_id: "cal-001", settings:, target:)

    expect { profile.validate_complete! }
      .to raise_error(Lithop::InputError, /missing measurements.*white_point.*black_point/)
  end
end

# frozen_string_literal: true

RSpec.describe Lithop::Calibration::RecipeSelector do
  let(:settings) { Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0) }
  let(:palette) { Lithop::Palette.new }

  it "uses averaged measured chroma instead of nominal recipe coverage" do
    profile = measured_calibration_profile(settings) do |candidate|
      patches = candidate.data.fetch("patches")
      cyan = patches.find { |patch| patch.fetch("recipe") == pigment_counts("cyan") }
      magenta = patches.find { |patch| patch.fetch("recipe") == pigment_counts("magenta") }
      cyan.fetch("measurements").first["transmitted_srgb"] = [1.0, 0.0, 1.0]
      magenta.fetch("measurements").first["transmitted_srgb"] = [0.0, 1.0, 1.0]
    end
    selector = described_class.new(profile:, palette:)

    expect(selector.nearest([1.0, 0.0, 0.0]).magenta).to eq(7)
  end

  def pigment_counts(pigment)
    Lithop::Palette::MATERIALS.to_h { |material| [material.to_s, material.to_s == pigment ? 7 : 0] }
  end
end

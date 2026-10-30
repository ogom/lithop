# frozen_string_literal: true

RSpec.describe Lithop::Calibration::ThicknessSelector do
  let(:settings) { Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0) }

  it "maps density endpoints to the measured brightest and darkest White stages" do
    profile = measured_calibration_profile(settings)
    selector = described_class.new(profile:, settings:)

    expect(selector.call([0.0, 1.0])).to eq([0.74, 1.94])
  end

  it "rejects White stages without a measurable luminance range" do
    profile = measured_calibration_profile(settings) do |candidate|
      candidate.data.fetch("patches").select { |patch| patch.fetch("kind") == "white_thickness" }.each do |patch|
        patch.fetch("measurements").first["luminance"] = 50.0
      end
    end

    expect { described_class.new(profile:, settings:) }
      .to raise_error(Lithop::InputError, /span more than one luminance/)
  end
end

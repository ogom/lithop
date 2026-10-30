# frozen_string_literal: true

RSpec.describe Lithop::Thickness do
  let(:settings) { Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0) }

  it "makes dense CMY pixels thicker and aligns every value to a layer boundary" do
    heights = described_class.from_cmy_density([0.0, 0.5, 1.0], settings)

    expect(heights).to eq([0.74, 1.38, 1.94])
  end

  it "rejects out-of-range CMY density" do
    expect { described_class.from_cmy_density([1.1], settings) }
      .to raise_error(Lithop::InputError, /CMY density must be between 0 and 1/)
  end

  it "normalizes the reference image density to its exact thickness range" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    expect(described_class.from_cmy_density([0.2, 0.5, 0.8], settings)).to eq(
      [0.74, 1.38, 1.94]
    )
  end

  it "keeps continuous reference White heights separate from slicer layer boundaries" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    expect(described_class.continuous_from_density([0.2, 0.5, 0.8], settings)).to match(
      [0.74, be_within(1e-12).of(1.34), 1.94]
    )
  end
end

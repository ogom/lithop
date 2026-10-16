# frozen_string_literal: true

RSpec.describe Lithop::BoxGeometry do
  it "creates a closed box with the requested Z bounds" do
    geometry = described_class.new(width: 2.0, height: 3.0, z_min: 0.2, z_max: 0.5)

    report = Lithop::MeshValidator.report!(geometry.each_triangle)

    expect(geometry.triangle_count).to eq(12)
    expect(report.volume).to be_within(1e-9).of(1.8)
  end
end

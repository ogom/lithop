# frozen_string_literal: true

RSpec.describe Lithop::Geometry do
  it "creates a closed, consistently oriented mesh with changing heights" do
    geometry = described_class.new(
      heights: [1.0, 2.0, 2.0, 1.0, 2.0, 2.0],
      columns: 2,
      rows: 1,
      x_boundaries: [0.0, 1.0, 2.0],
      y_boundaries: [0.0, 1.0]
    )

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(report.triangle_count).to eq(20)
    expect(report.component_volumes).to eq([3.5])
    expect(report.volume).to eq(3.5)
  end

  it "rejects a closed mesh whose faces point inward" do
    geometry = described_class.new(
      heights: [1.0, 1.0, 1.0, 1.0],
      columns: 1,
      rows: 1,
      x_boundaries: [0.0, 1.0],
      y_boundaries: [0.0, 1.0]
    )
    inward = geometry.each_triangle.map(&:reverse)

    expect { Lithop::MeshValidator.report!(inward) }
      .to raise_error(Lithop::InputError, "mesh is not outward-facing")
  end

  it "uses a perimeter fan for the reference profile bottom" do
    geometry = described_class.new(
      heights: [1.0, 1.0, 1.0, 1.0, 1.0, 1.0],
      columns: 2, rows: 1,
      x_boundaries: [0.0, 1.0, 2.0], y_boundaries: [0.0, 1.0],
      optimize_bottom: true
    )

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(report.triangle_count).to eq(22)
    expect(report.volume).to be_within(1e-9).of(2.0)
  end

  it "closes an optimized bottom when the final Y cell is partial" do
    geometry = described_class.new(
      heights: Array.new(6, 1.0),
      columns: 1, rows: 2,
      x_boundaries: [0.0, 1.0], y_boundaries: [0.0, 1.0, 1.5],
      optimize_bottom: true
    )

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(report.volume).to be_within(1e-9).of(1.5)
  end
end

# frozen_string_literal: true

RSpec.describe Lithop::ZRegionModel do
  it "clips material layers at arbitrary Z boundaries" do
    cell_class = Data.define(:materials)
    model_class = Data.define(:columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells)
    model = model_class.new(
      columns: 1,
      rows: 1,
      x_boundaries: [0.0, 1.0],
      y_boundaries: [0.0, 1.0],
      z_boundaries: [0.0, 0.1, 0.2, 0.3, 0.4],
      cells: [cell_class.new(materials: %i[white cyan magenta yellow])]
    )

    region = described_class.new(model:, z_range: 0.15...0.35)

    expect(region.z_boundaries).to eq([0.15, 0.2, 0.3, 0.35])
    expect(region.cells.first.materials).to eq(%i[cyan magenta yellow])
    expect(region.materials).to eq(%i[cyan magenta yellow])
  end
end

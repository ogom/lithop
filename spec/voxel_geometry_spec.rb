# frozen_string_literal: true

RSpec.describe Lithop::VoxelGeometry do
  it "maps material row zero to the model's positive-Y edge" do
    model = double(
      "MaterialModel",
      x_boundaries: [0.0, 1.0],
      y_boundaries: [0.0, 1.0, 2.0],
      z_boundaries: [0.0, 0.1]
    )
    allow(model).to receive(:material_at).and_return(:cyan)
    topology = Lithop::VoxelTopology.new(model:, material: :cyan)

    expect(topology.vertex(0, 0, 0, [0, 0, 0]).y).to eq(2.0)
    expect(topology.vertex(0, 2, 0, [0, 1, 0]).y).to eq(0.0)
  end

  it "partitions an asymmetric CMYW volume into closed, outward-facing material meshes" do
    settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0)
    heights = [1.11, 1.23, 1.35, 1.47, 1.59, 1.71, 1.83, 1.95, 2.07]
    model = Lithop::MaterialModel.new(
      cmys: Array.new(9, [1.0, 1.0, 1.0]),
      heights:,
      settings:
    )

    reports = model.materials.to_h do |material|
      geometry = described_class.new(model:, material:)
      report = Lithop::MeshValidator.report!(geometry.each_triangle)
      expect(report.component_volumes).to all(be > 0.0)
      [material, report]
    end

    expected_volume = model.cells.each_with_index.sum do |cell, index|
      row, column = index.divmod(model.columns)
      width = model.x_boundaries.fetch(column + 1) - model.x_boundaries.fetch(column)
      height = model.y_boundaries.fetch(row + 1) - model.y_boundaries.fetch(row)
      width * height * cell.height
    end
    expect(reports.values.sum(&:volume)).to be_within(1e-9).of(expected_volume)

    model.z_boundaries.each_cons(2).with_index do |_bounds, layer|
      model.rows.times do |row|
        model.columns.times do |column|
          assigned = Lithop::Palette::MATERIALS.count do |material|
            model.material_at(layer, row, column) == material
          end
          expected = model.cells.fetch((row * model.columns) + column).materials.fetch(layer, nil) ? 1 : 0
          expect(assigned).to eq(expected)
        end
      end
    end
  end

  it "keeps diagonally touching regions topologically separate" do
    model = double(
      "MaterialModel",
      columns: 2,
      rows: 2,
      x_boundaries: [0.0, 1.0, 2.0],
      y_boundaries: [0.0, 1.0, 2.0],
      z_boundaries: [0.0, 0.1]
    )
    allow(model).to receive(:material_at) do |layer, row, column|
      :cyan if layer.zero? && [[0, 0], [1, 1]].include?([row, column])
    end
    geometry = described_class.new(model:, material: :cyan)

    expect(geometry.triangle_count).to eq(24)
    expect(geometry.each_triangle.count).to eq(24)
    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(report.component_volumes).to all(be_within(1e-12).of(0.1))
    expect(report.volume).to be_within(1e-12).of(0.2)
  end
end

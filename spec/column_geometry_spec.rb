# frozen_string_literal: true

RSpec.describe Lithop::ColumnGeometry do
  it "creates a closed pigment mesh from adjacent cells with different layer counts" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 2.0, height: 1.0, grid_columns: 2, grid_rows: 1
    )
    model = Lithop::MaterialModel.new(
      cmys: Array.new(6, [0.0, 0.0, 0.0]),
      cell_cmys: [[1.0, 0.0, 0.0], [0.5, 0.0, 0.0]],
      heights: Array.new(6, 1.0),
      settings:
    )
    geometry = described_class.new(model:, material: :cyan)

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(geometry.triangle_count).to eq(report.triangle_count)
    expect(report.triangle_count).to be < 100
    expect(report.volume).to be_positive
  end

  it "keeps diagonally touching pigment columns as separate closed components" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 2.0, height: 2.0, grid_columns: 2, grid_rows: 2
    )
    model = Lithop::MaterialModel.new(
      cmys: Array.new(9, [0.0, 0.0, 0.0]),
      cell_cmys: [
        [1.0, 0.0, 0.0], [0.0, 0.0, 0.0],
        [0.0, 0.0, 0.0], [1.0, 0.0, 0.0]
      ],
      heights: Array.new(9, 1.0),
      settings:
    )
    geometry = described_class.new(model:, material: :cyan)

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(geometry.triangle_count).to eq(report.triangle_count)
    expect(report.component_volumes.length).to eq(2)
    expect(report.component_volumes).to all(be_positive)
  end

  it "separates an edge contact whose endpoints are joined through neighbouring voxels" do
    cell = Data.define(:materials)
    cells = [
      cell.new(materials: [:cyan]), cell.new(materials: %i[cyan cyan]),
      cell.new(materials: [:cyan]), cell.new(materials: %i[white cyan]),
      cell.new(materials: [:cyan]), cell.new(materials: %i[cyan cyan])
    ]
    model_class = Data.define(:columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells) do
      def material_at(layer, row, column)
        return if layer.negative? || row.negative? || column.negative?
        return if row >= rows || column >= columns

        cells.fetch((row * columns) + column).materials[layer]
      end
    end
    model = model_class.new(
      columns: 2, rows: 3,
      x_boundaries: [0.0, 1.0, 2.0], y_boundaries: [0.0, 1.0, 2.0, 3.0],
      z_boundaries: [0.0, 1.0, 2.0], cells:
    )
    geometry = described_class.new(model:, material: :cyan)

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(geometry.triangle_count).to eq(report.triangle_count)
    expect(report.component_volumes.sum).to be_within(1e-12).of(8.0)
  end

  it "separates a vertical edge contact bridged below and above" do
    cell = Data.define(:materials)
    cells = [
      cell.new(materials: %i[cyan cyan cyan]), cell.new(materials: [:cyan]),
      cell.new(materials: %i[white white cyan]), cell.new(materials: %i[cyan cyan cyan])
    ]
    model_class = Data.define(:columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells) do
      def material_at(layer, row, column)
        return if layer.negative? || row.negative? || column.negative?
        return if row >= rows || column >= columns

        cells.fetch((row * columns) + column).materials[layer]
      end
    end
    model = model_class.new(
      columns: 2, rows: 2,
      x_boundaries: [0.0, 1.0, 2.0], y_boundaries: [0.0, 1.0, 2.0],
      z_boundaries: [0.0, 1.0, 2.0, 3.0], cells:
    )
    geometry = described_class.new(model:, material: :cyan)

    report = Lithop::MeshValidator.report!(geometry.each_triangle)
    expect(geometry.triangle_count).to eq(report.triangle_count)
    expect(report.component_volumes.sum).to be_within(1e-12).of(8.0)
  end
end

# frozen_string_literal: true

RSpec.describe Lithop::TileLayout do
  it "chooses the factor pair whose physical tiles are closest to square" do
    settings = Lithop::Settings.new(
      width: 144.0, height: 108.0, grid_columns: 12, grid_rows: 12, tile_count: 6
    )

    layout = described_class.new(settings)

    expect([layout.rows, layout.columns]).to eq([2, 3])
    expect(layout.tiles.map { |tile| [tile.width, tile.height] }.uniq).to eq([[48.0, 54.0]])
    expect(layout.tiles.map(&:id)).to eq(%w[
                                           tile_r01_c01 tile_r01_c02 tile_r01_c03 tile_r02_c01 tile_r02_c02 tile_r02_c03
                                         ])
  end

  it "keeps prime counts exact and prefers the better physical orientation" do
    settings = Lithop::Settings.new(
      width: 140.0, height: 104.0, grid_columns: 10, grid_rows: 10, tile_count: 5
    )

    layout = described_class.new(settings)

    expect([layout.rows, layout.columns]).to eq([1, 5])
    expect(layout.tiles.length).to eq(5)
  end

  it "uses one row for a two-way landscape split" do
    settings = Lithop::Settings.new(
      width: 140.0, height: 104.0, grid_columns: 10, grid_rows: 10, tile_count: 2
    )

    expect(described_class.new(settings).then { |layout| [layout.rows, layout.columns] }).to eq([1, 2])
  end

  it "shares existing cell boundaries when the grid is not divisible" do
    settings = Lithop::Settings.new(
      width: 5.0, height: 4.0, grid_columns: 5, grid_rows: 4, tile_count: 6
    )

    layout = described_class.new(settings)

    expect([layout.rows, layout.columns]).to eq([2, 3])
    expect(layout.tiles.first.bounds).to eq(x_min: 0.0, x_max: 2.0, y_min: 2.0, y_max: 4.0)
    expect(layout.tiles.fetch(1).bounds).to eq(x_min: 2.0, x_max: 4.0, y_min: 2.0, y_max: 4.0)
    expect(layout.tiles.fetch(2).bounds).to eq(x_min: 4.0, x_max: 5.0, y_min: 2.0, y_max: 4.0)
    expect(layout.tiles.last.bounds).to eq(x_min: 4.0, x_max: 5.0, y_min: 0.0, y_max: 2.0)
  end
end

RSpec.describe Lithop::TileMaterialModel do
  it "partitions every whole-image material cell once without changing its layers" do
    settings = Lithop::Settings.new(
      width: 5.0, height: 4.0, grid_columns: 5, grid_rows: 4, tile_count: 6
    )
    vertex_count = (settings.columns + 1) * (settings.rows + 1)
    cmys = Array.new(vertex_count, [0.0, 0.0, 0.0])
    cell_cmys = Array.new(settings.columns * settings.rows) do |index|
      [index.fdiv(settings.columns * settings.rows), 0.2, 0.1]
    end
    heights = Array.new(vertex_count, settings.effective_minimum_thickness)
    model = Lithop::MaterialModel.new(cmys:, cell_cmys:, heights:, settings:)
    reconstructed = Array.new(model.cells.length)

    Lithop::TileLayout.new(settings).tiles.each do |tile|
      sliced = described_class.new(model:, tile:)
      sliced.rows.times do |row|
        sliced.columns.times do |column|
          source_index = ((tile.row_start + row) * model.columns) + tile.column_start + column
          reconstructed[source_index] = sliced.cells.fetch((row * sliced.columns) + column)
        end
      end
    end

    expect(reconstructed).to eq(model.cells)
  end
end

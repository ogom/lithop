# frozen_string_literal: true

RSpec.describe Lithop::MaterialModel do
  let(:settings) { Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0) }

  it "uses explicit color cells while retaining vertex-based thickness samples" do
    model = described_class.new(
      cmys: Array.new(4, [0.0, 0.0, 0.0]),
      cell_cmys: [[1.0, 0.0, 0.0]],
      heights: Array.new(4, settings.effective_minimum_thickness),
      settings:
    )

    expect(model.cells.fetch(0).recipe.cyan).to eq(settings.color_layer_count)
    expect(model.cells.fetch(0).height).to eq(settings.effective_minimum_thickness)
  end

  it "places one White base layer, seven subtractive color layers, and variable White layers" do
    green = [1.0, 0.0, 1.0]
    model = described_class.new(
      cmys: [green, green, green, green],
      heights: [1.11, 1.11, 1.11, 1.11],
      settings:
    )

    expect(model.cells.fetch(0).materials).to eq(
      %i[white yellow yellow yellow yellow cyan cyan cyan white white white white white white]
    )
    expect(model.z_boundaries).to eq(
      [0.0, 0.1, 0.18, 0.26, 0.34, 0.42, 0.5, 0.58, 0.66, 0.74, 0.82, 0.9, 0.98, 1.06, 1.14]
    )
  end

  it "represents purple with only cyan and magenta in the color region" do
    purple = [1.0, 1.0, 0.0]
    model = described_class.new(
      cmys: [purple, purple, purple, purple],
      heights: [1.05, 1.05, 1.05, 1.05],
      settings:
    )

    expect(model.cells.fetch(0).materials.slice(1, 7).uniq).to contain_exactly(:cyan, :magenta)
    expect(model.cells.fetch(0).materials.count(:white)).to be >= 3
  end

  it "rejects a thickness that cannot contain the minimum top white layers" do
    expect do
      Lithop::Settings.new(
        width: 1.0,
        height: 1.0,
        pixel_size: 1.0,
        minimum_thickness: 0.67,
        maximum_thickness: 0.73
      )
    end.to raise_error(Lithop::ConfigurationError, /no printable layer boundary/)
  end

  it "supports a four-layer comparison selected through settings" do
    comparison_settings = Lithop::Settings.new(
      width: 1.0,
      height: 1.0,
      pixel_size: 1.0,
      minimum_thickness: 0.99,
      color_layer_count: 4
    )
    model = described_class.new(
      cmys: Array.new(4, [0.0, 0.0, 0.0]),
      heights: Array.new(4, 0.99),
      settings: comparison_settings
    )

    expect(model.cells.fetch(0).recipe.layer_count).to eq(4)
  end

  it "builds the reference one-layer base, seven-layer color region, and upper White region" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )
    model = described_class.new(
      cmys: Array.new(4, [1.0, 0.0, 0.0]),
      heights: Array.new(4, 1.0),
      settings: reference
    )

    expect(model.cells.fetch(0).materials).to eq(
      %i[white cyan cyan cyan cyan cyan cyan cyan white white white white]
    )
    expect(model.z_boundaries).to eq(
      [0.0, 0.1, 0.18, 0.26, 0.34, 0.42, 0.5, 0.58, 0.66, 0.74, 0.82, 0.9, 0.98]
    )
  end
end

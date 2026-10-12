# frozen_string_literal: true

RSpec.describe Lithop::Calibration::Target do
  subject(:target) { described_class.new(settings:) }

  let(:settings) { Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0) }

  it "contains every seven-layer recipe and eight White thickness stages" do
    recipes = target.recipe_patches.map { |patch| patch.recipe.to_h.fetch(:counts) }

    expect(recipes.uniq.length).to eq(120)
    expect(target.white_patches.map(&:height)).to eq(
      [1.0, 1.16, 1.32, 1.48, 1.64, 1.8, 2.0, 2.14689422]
    )
    expect(target.patches.length).to eq(128)
  end

  it "uses a 140 by 104 mm plate and an extra orientation column" do
    expect([target.width, target.height]).to eq([140.0, 104.0])
    expect([target.columns, target.rows]).to eq([16, 9])
    expect(target.cells.length).to eq(144)
    expect(target.x_boundaries.last).to eq(140.0)
    expect(target.y_boundaries.last).to eq(104.0)
  end

  it "places recipes from the upper-left and White stages on the bottom row" do
    expect(target.recipe_patches.first).to have_attributes(id: "R000", row: 0, column: 0)
    expect(target.recipe_patches.last).to have_attributes(id: "R119", row: 7, column: 14)
    expect(target.white_patches.first).to have_attributes(id: "W00", row: 8, column: 0)
    expect(target.white_patches.last).to have_attributes(id: "W07", row: 8, column: 7)
  end
end

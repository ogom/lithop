# frozen_string_literal: true

RSpec.describe Lithop::Palette do
  subject(:palette) { described_class.new }

  it "enumerates every seven-layer CMYW recipe by default" do
    expect(palette.recipes.length).to eq(120)
    expect(palette.recipes).to all(satisfy { |recipe| recipe.layer_count == 7 })
    expect(palette.recipes.map(&:layers).uniq.length).to eq(120)
  end

  it "enumerates all 35 recipes when the comparison model uses four color layers" do
    four_layer_palette = described_class.new(layer_count: 4)

    expect(four_layer_palette.recipes.length).to eq(35)
    expect(four_layer_palette.recipes).to all(satisfy { |recipe| recipe.layer_count == 4 })
    expect(four_layer_palette.recipes.map(&:layers).uniq.length).to eq(35)
  end

  it "selects exact uncalibrated recipes for the CMY primaries" do
    expect(palette.nearest([1.0, 0.0, 0.0]).layers).to eq([:cyan] * 7)
    expect(palette.nearest([0.0, 1.0, 0.0]).layers).to eq([:magenta] * 7)
    expect(palette.nearest([0.0, 0.0, 1.0]).layers).to eq([:yellow] * 7)
  end

  it "creates green by stacking only cyan and yellow pigments" do
    recipe = palette.nearest([1.0, 0.0, 1.0])

    expect(recipe.pigments).to eq(described_class::SUBTRACTIVE_MIXES.fetch(:green))
    expect(recipe.white).to be_zero
  end

  it "creates purple by stacking only cyan and magenta pigments" do
    recipe = palette.nearest([1.0, 1.0, 0.0])

    expect(recipe.pigments).to eq(described_class::SUBTRACTIVE_MIXES.fetch(:purple))
    expect(recipe.white).to be_zero
  end

  it "uses white when CMY coverage is zero" do
    expect(palette.nearest([0.0, 0.0, 0.0]).layers).to eq([:white] * 7)
  end

  it "orders every recipe as cyan, magenta, yellow, then white" do
    palette.recipes.each do |recipe|
      expected = Lithop::Palette::MATERIALS.flat_map { |material| [material] * recipe.public_send(material) }

      expect(recipe.layers).to eq(expected)
    end
  end

  it "uses the configured pigment order before white layers" do
    reversed_palette = described_class.new(pigment_order: %i[yellow magenta cyan])
    recipe = reversed_palette.nearest([1.0, 0.0, 1.0])

    expect(recipe.layers).to eq(%i[yellow yellow yellow yellow cyan cyan cyan])
  end

  it "exposes active pigments in serialized recipes" do
    recipe = palette.nearest([1.0, 0.0, 1.0])

    expect(recipe.to_h.fetch(:pigments)).to eq(%i[cyan yellow])
  end

  it "converts CMY coverage to an opaque RGB display color" do
    recipe = palette.nearest([1.0, 0.0, 0.0])

    expect(palette.display_color(recipe)).to eq("#00FFFFFF")
  end

  it "rejects invalid CMY samples" do
    expect { palette.nearest([1.0, -0.1, 0.5]) }.to raise_error(Lithop::InputError, /CMY/)
  end
end

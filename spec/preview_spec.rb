# frozen_string_literal: true

require "vips"

RSpec.describe Lithop::Preview do
  let(:model_class) { Data.define(:columns, :rows, :cells) }
  let(:palette) { Lithop::Palette.new }
  let(:recipes) do
    {
      cyan: palette.recipes.find { |recipe| recipe.cyan == 5 },
      magenta: palette.recipes.find { |recipe| recipe.magenta == 5 },
      yellow: palette.recipes.find { |recipe| recipe.yellow == 5 },
      white: palette.recipes.find { |recipe| recipe.white == 5 }
    }
  end
  let(:model) do
    cells = [
      cell(:cyan, 1.11, 9), cell(:magenta, 1.35, 11),
      cell(:yellow, 2.43, 20), cell(:white, 2.67, 22)
    ]
    model_class.new(columns: 2, rows: 2, cells:)
  end

  def cell(material, height, total_layers)
    recipe = recipes.fetch(material)
    remaining_white = total_layers - recipe.layers.length
    Lithop::MaterialModel::Cell.new(
      height:,
      recipe:,
      materials: [*recipe.layers, *Array.new(remaining_white, :white)]
    )
  end

  def pixels(path)
    image = Vips::Image.new_from_file(path.to_s)
    Array.new(image.height) do |row|
      Array.new(image.width) { |column| image.getpoint(column, row).map(&:round) }
    end
  end

  it "writes nominal material color and relative transmission in model row order" do
    Dir.mktmpdir do |directory|
      material = File.join(directory, "preview.png")
      transmission = File.join(directory, "transmission.png")

      described_class.write_material(material, model:, minimum: 1.11, maximum: 2.67)
      described_class.write_transmission(transmission, model:, minimum: 1.11, maximum: 2.67)

      expected_material = [
        [[73, 255, 255], [216, 62, 216]],
        [[39, 39, 11], [0, 0, 0]]
      ]
      expected_transmission = [
        [[255], [216]],
        [[39], [0]]
      ]
      expect(pixels(material)).to eq(expected_material)
      expect(pixels(transmission)).to eq(expected_transmission)
    end
  end

  it "writes cell thickness and comparable per-material layer-count masks" do
    Dir.mktmpdir do |directory|
      thickness = File.join(directory, "thickness.png")
      cyan = File.join(directory, "cyan-mask.png")

      described_class.write_thickness(thickness, model:, minimum: 1.11, maximum: 2.67)
      described_class.write_mask(cyan, model:, material: :cyan)

      expected_thickness = [
        [[0], [39]],
        [[216], [255]]
      ]
      expected_cyan = [
        [[58], [0]],
        [[0], [0]]
      ]
      expect(pixels(thickness)).to eq(expected_thickness)
      expect(pixels(cyan)).to eq(expected_cyan)
    end
  end

  it "renders continuous White heights independently of quantized material cells" do
    Dir.mktmpdir do |directory|
      thickness = File.join(directory, "continuous-thickness.png")

      described_class.write_thickness(
        thickness, model:, minimum: 1.11, maximum: 2.67,
                   heights: [1.11, 1.89, 2.28, 2.67]
      )

      expect(pixels(thickness)).to eq([[[0], [127]], [[191], [255]]])
    end
  end

  it "can brighten relative transmission without changing material recipes" do
    Dir.mktmpdir do |directory|
      material = File.join(directory, "gamma-preview.png")

      described_class.write_material(
        material, model:, minimum: 1.11, maximum: 2.67, transmission_gamma: 0.5
      )

      expect(pixels(material)).to eq(
        [[[73, 255, 255], [235, 67, 235]], [[100, 100, 28], [0, 0, 0]]]
      )
    end
  end
end

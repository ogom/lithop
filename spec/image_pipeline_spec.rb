# frozen_string_literal: true

require "vips"

RSpec.describe Lithop::ImagePipeline do
  let(:settings) { Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0) }

  it "renders a bounded placement preview through the common SVG pipeline" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "preview.svg")
      File.write(
        path,
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 1">' \
        '<rect width="2" height="1" fill="#0086D6"/></svg>'
      )
      preview_settings = Lithop::Settings.new(
        width: 140.0, height: 104.0, pixel_size: 0.22, brightness: 5.0,
        margin_top: 2.0, margin_right: 2.0, margin_bottom: 2.0, margin_left: 2.0
      )

      png = described_class.new(preview_settings).preview_png(path, maximum_width: 320, maximum_height: 240)
      image = Vips::Image.new_from_buffer(png, "")

      expect(png).to start_with("\x89PNG\r\n\x1A\n".b)
      expect(image.width).to be <= 321
      expect(image.height).to be <= 241
      expect(image.get("vips-loader")).to eq("pngload_buffer")
    end
  end

  it "applies brightness, contrast, and saturation before common image sampling" do
    Dir.mktmpdir do |directory|
      gray = write_solid(directory, "gray.png", [96, 96, 96])
      muted_red = write_solid(directory, "muted-red.png", [220, 160, 160])

      neutral_gray = described_class.new(settings).call(gray)
      brighter = described_class.new(
        Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0, brightness: 20.0)
      ).call(gray)
      contrasted = described_class.new(
        Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0, contrast: 100.0)
      ).call(gray)
      neutral_red = described_class.new(settings).call(muted_red)
      saturated = described_class.new(
        Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0, saturation: 100.0)
      ).call(muted_red)

      expect(brighter.white_densities.first).to be < neutral_gray.white_densities.first
      expect(contrasted.white_densities.first).to be > neutral_gray.white_densities.first
      expect(saturated.cmys.first.sum).to be > neutral_red.cmys.first.sum
    end
  end

  it "keeps a pale neutral reference color in White while preserving its density" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "pale.png")
      Vips::Image.new_from_memory(([245, 245, 245] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)

      expect(result.color_cells).to eq([[0.0, 0.0, 0.0]])
      expect(result.cmy_densities.max).to be_positive
    end
  end

  it "preserves pale Yellow in the reference layout" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "pale-yellow.png")
      Vips::Image.new_from_memory(([255, 245, 220] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)

      expect(result.color_cells.fetch(0).fetch(2)).to be > 0.08
    end
  end

  it "does not promote ordinary pale Yellow to a full material-display channel" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      recipes = [[254, 253, 222], [253, 253, 228]].map do |rgb|
        path = write_solid(directory, "pale-yellow-#{rgb.join("-")}.png", rgb)
        result = described_class.new(reference).call(path)
        Lithop::Palette.new.nearest(result.color_cells.fetch(0))
      end

      expect(recipes.map { |recipe| [recipe.cyan, recipe.magenta, recipe.yellow, recipe.white] })
        .to eq([[0, 0, 1, 6], [0, 0, 1, 6]])
    end
  end

  it "removes very pale Cyan, Magenta, and Yellow when pale-color suppression is enabled" do
    reference = Lithop::Settings.new(
      layout_profile: "standard", suppress_pale_colors: true,
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      colors = { cyan: [230, 255, 255], magenta: [255, 230, 255], yellow: [255, 255, 230] }
      cells = colors.map do |name, rgb|
        path = write_solid(directory, "pale-#{name}.png", rgb)
        described_class.new(reference).call(path).color_cells.fetch(0)
      end

      expect(cells).to all(eq([0.0, 0.0, 0.0]))
    end
  end

  it "preserves very pale Cyan, Magenta, and Yellow when pale-color suppression is disabled" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      colors = { cyan: [230, 255, 255], magenta: [255, 230, 255], yellow: [255, 255, 230] }
      recipes = colors.map do |name, rgb|
        path = write_solid(directory, "pale-#{name}.png", rgb)
        result = described_class.new(reference).call(path)
        Lithop::Palette.new.nearest(result.color_cells.fetch(0))
      end

      expect(recipes.map { |recipe| [recipe.cyan, recipe.magenta, recipe.yellow, recipe.white] })
        .to eq([[1, 0, 0, 6], [0, 1, 0, 6], [0, 0, 1, 6]])
    end
  end

  it "preserves five-percent Cyan and Magenta in marked material-display SVGs" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      { cyan: [242, 249, 253], magenta: [254, 242, 249] }.each do |name, rgb|
        path = write_solid_svg(directory, "#{name}-five-percent.svg", rgb, material_display: true)
        result = described_class.new(reference).call(path)

        expect(result.color_cells.fetch(0)).not_to eq([0.0, 0.0, 0.0])
      end
    end
  end

  it "maps dark neutral reference pixels to the CMY brown recipe" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "black.png")
      Vips::Image.new_from_memory(([0, 0, 0] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)

      expect(result.color_cells).to eq([[1.0 / 7, 1.0 / 7, 1.0 / 7]])
      recipe = Lithop::Palette.new(layer_count: 7).nearest(result.color_cells.fetch(0))
      expect([recipe.cyan, recipe.magenta, recipe.yellow, recipe.white]).to eq([1, 1, 1, 4])
    end
  end

  it "maps a dark warm SVG line color to the three-layer CMY brown recipe" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "warm-line.png")
      Vips::Image.new_from_memory(([90, 75, 40] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)
      recipe = Lithop::Palette.new(layer_count: 7).nearest(result.color_cells.fetch(0))

      expect([recipe.cyan, recipe.magenta, recipe.yellow, recipe.white]).to eq([1, 1, 1, 4])
    end
  end

  it "keeps an antialiased warm brown line as the three-layer CMY brown recipe" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "antialiased-line.png")
      Vips::Image.new_from_memory(([180, 165, 120] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)
      recipe = Lithop::Palette.new(layer_count: 7).nearest(result.color_cells.fetch(0))

      expect([recipe.cyan, recipe.magenta, recipe.yellow, recipe.white]).to eq([1, 1, 1, 4])
    end
  end

  it "keeps a one-corner brown line as the three-layer CMY brown recipe" do
    reference = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "thin-brown.png")
      pixels = [0, 0, 0, 255, 255, 255, 255, 255, 255, 255, 255, 255]
      Vips::Image.new_from_memory(pixels.pack("C*"), 2, 2, 3, :uchar).pngsave(path)
      result = described_class.new(reference).call(path)

      recipe = Lithop::Palette.new(layer_count: 7).nearest(result.color_cells.fetch(0))
      expect([recipe.cyan, recipe.magenta, recipe.yellow, recipe.white]).to eq([1, 1, 1, 4])
    end
  end

  it "converts sRGB chroma to CMY while keeping CMY density separate" do
    Dir.mktmpdir do |directory|
      bright = described_class.new(settings).call(write_solid(directory, "bright.png", [0, 255, 255]))
      dark = described_class.new(settings).call(write_solid(directory, "dark.png", [0, 128, 128]))

      expect(bright.cmys.uniq).to eq([[1.0, 0.0, 0.0]])
      expect(dark.cmys.uniq).to eq([[128.0 / 255, 0.0, 0.0]])
      expect(dark.cmy_densities.first).to be > bright.cmy_densities.first
    end
  end

  it "computes Rec. 601 density for the continuous White surface" do
    Dir.mktmpdir do |directory|
      red = described_class.new(settings).call(write_solid(directory, "red.png", [255, 0, 0]))
      green = described_class.new(settings).call(write_solid(directory, "green.png", [0, 255, 0]))
      blue = described_class.new(settings).call(write_solid(directory, "blue.png", [0, 0, 255]))

      expect(red.white_densities.uniq).to contain_exactly(be_within(1e-12).of(0.701))
      expect(green.white_densities.uniq).to contain_exactly(be_within(1e-12).of(0.413))
      expect(blue.white_densities.uniq).to contain_exactly(be_within(1e-12).of(0.886))
    end
  end

  it "maps filament display colors in marked SVGs to pure material channels" do
    Dir.mktmpdir do |directory|
      colors = {
        cyan: [[0, 134, 214], [1.0, 0.0, 0.0]],
        magenta: [[236, 0, 140], [0.0, 1.0, 0.0]],
        yellow: [[252, 227, 0], [0.0, 0.0, 1.0]]
      }

      colors.each do |name, (rgb, expected_cmy)|
        path = write_solid_svg(directory, "#{name}.svg", rgb, material_display: true)
        result = described_class.new(settings).call(path)
        recipe = Lithop::Palette.new.nearest(result.cmys.first)

        expect(result.cmys.uniq).to eq([expected_cmy])
        expect(result.cmy_densities.uniq).to eq([1.0])
        expect(recipe.layers).to eq([name] * 7)
      end
    end
  end

  it "replaces the selected percentage of Yellow with Cyan or Magenta" do
    Dir.mktmpdir do |directory|
      path = write_solid_svg(directory, "yellow.svg", [252, 227, 0], material_display: true)

      { "cyan" => [0.2, 0.0, 0.8], "magenta" => [0.0, 0.2, 0.8] }.each do |color, expected|
        mixed_settings = Lithop::Settings.new(
          width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1,
          yellow_mix_color: color, yellow_mix_percent: 20.0
        )
        result = described_class.new(mixed_settings).call(path)
        recipe = Lithop::Palette.new.nearest(result.color_cells.fetch(0))

        expect(result.cmys.uniq).to eq([expected])
        expect(result.white_densities.uniq).to eq([1.0])
        expected_layers = color == "cyan" ? [1, 0, 6, 0] : [0, 1, 6, 0]
        expect([recipe.cyan, recipe.magenta, recipe.yellow, recipe.white]).to eq(expected_layers)
      end
    end
  end

  it "uses the CMY dark recipe for black and no pigment for white" do
    Dir.mktmpdir do |directory|
      black = described_class.new(settings).call(write_solid(directory, "black.png", [0, 0, 0]))
      white = described_class.new(settings).call(write_solid(directory, "white.png", [255, 255, 255]))

      expect(black.cmys.uniq).to eq([[1.0 / 7, 1.0 / 7, 1.0 / 7]])
      expect(white.cmys.uniq).to eq([[0.0, 0.0, 0.0]])
      expect(black.cmy_densities.uniq).to eq([1.0])
      expect(white.cmy_densities.uniq).to eq([0.0])
    end
  end

  it "applies EXIF orientation before sampling an asymmetric JPEG" do
    oriented_settings = Lithop::Settings.new(width: 2.0, height: 1.0, pixel_size: 1.0)

    Dir.mktmpdir do |directory|
      path = File.join(directory, "oriented.jpg")
      pixels = [
        [255, 0, 0], [0, 255, 0],
        [0, 0, 255], [0, 255, 255],
        [255, 0, 255], [255, 255, 0]
      ].flatten.pack("C*")
      image = Vips::Image.new_from_memory(pixels, 2, 3, 3, :uchar)
      image = image.mutate { |mutable| mutable.set_type! GObject::GINT_TYPE, "orientation", 6 }
      image.jpegsave(path, keep: :all, Q: 100, subsample_mode: :off)

      result = described_class.new(oriented_settings).call(path)

      expect([result.width, result.height]).to eq([3, 2])
      expect(result.cmys).to match(
        [approximately_cmy(0, 1, 0), approximately_cmy(1, 1, 0), approximately_cmy(0, 1, 1),
         approximately_cmy(0, 0, 1), approximately_cmy(1, 0, 0), approximately_cmy(1, 0, 1)]
      )
    end
  end

  it "composites transparent PNG pixels over White" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "transparent.png")
      pixels = ([0, 0, 0, 0] * 4).pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 4, :uchar).pngsave(path)

      result = described_class.new(settings).call(path)

      expect(result.cmys.uniq).to eq([[0.0, 0.0, 0.0]])
      expect(result.cmy_densities.uniq).to eq([0.0])
    end
  end

  it "covers the requested aspect ratio with a centered crop instead of distortion" do
    wide_settings = Lithop::Settings.new(width: 2.0, height: 1.0, pixel_size: 1.0)

    Dir.mktmpdir do |directory|
      path = File.join(directory, "wide.png")
      row = [[255, 0, 0], [255, 0, 0], [0, 255, 0], [0, 255, 0], [0, 0, 255], [0, 0, 255]]
      pixels = [*row, *row].flatten.pack("C*")
      Vips::Image.new_from_memory(pixels, 6, 2, 3, :uchar).pngsave(path)

      result = described_class.new(wide_settings).call(path)

      expect([result.width, result.height]).to eq([3, 2])
      expect(result.cmys).to match(
        [approximately_cmy(0, 1, 1), approximately_cmy(1, 0, 1), approximately_cmy(1, 0, 1),
         approximately_cmy(0, 1, 1), approximately_cmy(1, 0, 1), approximately_cmy(1, 0, 1)]
      )
    end
  end

  it "positions a cover crop independently on each axis" do
    left_settings = Lithop::Settings.new(
      width: 2.0, height: 1.0, pixel_size: 1.0, crop_position_x: 0.0
    )
    right_settings = Lithop::Settings.new(
      width: 2.0, height: 1.0, pixel_size: 1.0, crop_position_x: 1.0
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "four-colors.png")
      row = [
        [255, 0, 0], [255, 0, 0], [0, 255, 0],
        [0, 0, 255], [255, 255, 255], [255, 255, 255]
      ]
      Vips::Image.new_from_memory([*row, *row].flatten.pack("C*"), 6, 2, 3, :uchar).pngsave(path)

      left = described_class.new(left_settings).call(path)
      right = described_class.new(right_settings).call(path)

      expect(left.cmys.first(3)).to match(
        [approximately_cmy(0, 1, 1), approximately_cmy(0, 1, 1), approximately_cmy(1, 0, 1)]
      )
      expect(right.cmys.first(3)).to match(
        [approximately_cmy(1, 1, 0), approximately_cmy(0, 0, 0), approximately_cmy(0, 0, 0)]
      )
    end
  end

  it "zooms into the selected crop rectangle" do
    zoomed_settings = Lithop::Settings.new(
      width: 2.0, height: 1.0, pixel_size: 1.0, crop_scale: 0.5
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "zoom.png")
      row = [
        [255, 0, 0], [0, 255, 0], [0, 0, 255],
        [255, 255, 255], [255, 0, 0], [0, 255, 0]
      ]
      Vips::Image.new_from_memory(Array.new(4, row).flatten.pack("C*"), 6, 4, 3, :uchar).pngsave(path)

      result = described_class.new(zoomed_settings).call(path)

      expect(result.cmys.first(3)).to match(
        [approximately_cmy(1, 0, 1), approximately_cmy(1, 1, 0), approximately_cmy(0, 0, 0)]
      )
    end
  end

  it "contains the complete image and fills unused cells with White" do
    contain_settings = Lithop::Settings.new(
      width: 3.0, height: 3.0, pixel_size: 1.0, image_fit: "contain"
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "contained.png")
      row = Array.new(4, [255, 0, 0])
      Vips::Image.new_from_memory([*row, *row].flatten.pack("C*"), 4, 2, 3, :uchar).pngsave(path)

      result = described_class.new(contain_settings).call(path)

      expect(result.cmys.first(4)).to all(eq([0.0, 0.0, 0.0]))
      expect(result.cmys[4, 8]).to all(match(approximately_cmy(0, 1, 1)))
      expect(result.cmys.last(4)).to all(eq([0.0, 0.0, 0.0]))
    end
  end

  it "groups CMYW recipes into independent physical color cells" do
    separate_color_settings = Lithop::Settings.new(
      width: 4.0, height: 1.0, pixel_size: 1.0, color_pixel_size: 2.0
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "color-cells.png")
      row = [
        [255, 0, 0], [255, 0, 0], [255, 0, 0],
        [0, 0, 255], [0, 0, 255]
      ]
      Vips::Image.new_from_memory([*row, *row].flatten.pack("C*"), 5, 2, 3, :uchar).pngsave(path)

      result = described_class.new(separate_color_settings).call(path)

      expect(result.color_cells.length).to eq(4)
      expect(result.color_cells[0]).to eq(result.color_cells[1])
      expect(result.color_cells[0]).not_to eq(result.color_cells[2])
      expect(result.color_cells[2]).to eq(result.color_cells[3])
      expect(result.cmy_densities.length).to eq(10)
    end
  end

  it "adds individually specified White margins around the sampled image" do
    margin_settings = Lithop::Settings.new(
      width: 4.0,
      height: 4.0,
      pixel_size: 1.0,
      margin_top: 1.0,
      margin_right: 1.0,
      margin_bottom: 1.0,
      margin_left: 1.0
    )

    Dir.mktmpdir do |directory|
      result = described_class.new(margin_settings).call(write_solid(directory, "black.png", [0, 0, 0]))

      expect([result.width, result.height]).to eq([5, 5])
      expect(result.cmy_densities.first(5)).to all(eq(0.0))
      expect(result.cmy_densities.each_slice(5).map(&:first)).to all(eq(0.0))
      expect(result.cmy_densities.each_slice(5).map(&:last)).to all(eq(0.0))
      expect(result.cmy_densities.last(5)).to all(eq(0.0))
      expect(result.cmy_densities.fetch(12)).to eq(1.0)
    end
  end

  it "assigns equal density to the three CMY primaries" do
    Dir.mktmpdir do |directory|
      densities = {
        cyan: [0, 255, 255],
        magenta: [255, 0, 255],
        yellow: [255, 255, 0]
      }.transform_values do |rgb|
        described_class.new(settings).call(write_solid(directory, "#{rgb.join("-")}.png", rgb)).cmy_densities.first
      end

      expect(densities.values).to all(be_within(0.0001).of(1.0 / 3.0))
    end
  end

  it "normalizes sRGB chroma by its maximum channel and computes density from unnormalized sRGB" do
    Dir.mktmpdir do |directory|
      result = described_class.new(settings).call(write_solid(directory, "sample.png", [64, 128, 255]))

      expect(result.cmys.first).to match(
        [be_within(0.0001).of(191.0 / 255.0), be_within(0.0001).of(127.0 / 255.0), 0.0]
      )
      expect(result.cmy_densities.first).to be_within(0.0001).of((191.0 + 127.0) / 255.0 / 3.0)
    end
  end

  it "converts an embedded Display P3 profile to sRGB" do
    profile = "/System/Library/ColorSync/Profiles/Display P3.icc"
    skip "Display P3 ICC profile is unavailable" unless File.file?(profile)

    Dir.mktmpdir do |directory|
      path = write_solid(directory, "display-p3.png", [255, 128, 0], profile:)
      result = described_class.new(settings).call(path)

      expect(result.cmys.first[0]).to be_within(0.0001).of(0.0)
      expect(result.cmys.first[1]).to be_between(0.51, 0.56)
      expect(result.cmys.first[2]).to be_within(0.0001).of(1.0)
    end
  end

  it "increases density with the number of subtractive primaries" do
    Dir.mktmpdir do |directory|
      colors = {
        white: [255, 255, 255],
        cyan: [0, 255, 255],
        green: [0, 255, 0],
        black: [0, 0, 0]
      }
      densities = colors.transform_values do |rgb|
        described_class.new(settings).call(write_solid(directory, "#{rgb.join("-")}.png", rgb)).cmy_densities.first
      end

      expect(densities.values).to match([be_within(0.0001).of(0.0), be_within(0.0001).of(1.0 / 3.0),
                                         be_within(0.0001).of(2.0 / 3.0), be_within(0.0001).of(1.0)])
    end
  end

  def write_solid(directory, name, rgb, profile: nil)
    path = File.join(directory, name)
    options = profile ? { profile: } : {}
    Vips::Image.new_from_memory((rgb * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(path, **options)
    path
  end

  def write_solid_svg(directory, name, rgb, material_display: false)
    path = File.join(directory, name)
    marker = material_display ? ' data-lithop-color-encoding="material-display"' : ""
    red, green, blue = rgb
    color = format("#%<red>02X%<green>02X%<blue>02X", red:, green:, blue:)
    File.write(
      path,
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 2 2\"#{marker}>" \
      "<rect width=\"2\" height=\"2\" fill=\"#{color}\"/></svg>"
    )
    path
  end

  def approximately_cmy(cyan, magenta, yellow)
    [cyan, magenta, yellow].map { |value| be_within(0.01).of(value) }
  end
end

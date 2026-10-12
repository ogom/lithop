# frozen_string_literal: true

require "vips"

RSpec.describe "SVG image input" do
  let(:settings) { Lithop::Settings.new(width: 2.0, height: 1.0, pixel_size: 1.0) }

  it "detects an extensionless SVG by content and samples its colors" do
    with_svg("input", <<~SVG) do |path|
      <?xml version="1.0" encoding="UTF-8"?>
      <!-- The extension is intentionally absent. -->
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 3 2">
        <rect width="3" height="2" fill="#00ffff"/>
      </svg>
    SVG
      result = Lithop::ImagePipeline.new(settings).call(path)

      expect([result.width, result.height]).to eq([3, 2])
      expect(result.cmys).to all(eq([1.0, 0.0, 0.0]))
    end
  end

  it "accepts physical dimensions and composites transparency over White" do
    with_svg("transparent.SVG", <<~SVG) do |path|
      <svg xmlns="http://www.w3.org/2000/svg" width="25.4mm" height="12.7mm" viewBox="0 0 2 1">
        <rect width="2" height="1" fill="#000000" fill-opacity="0"/>
      </svg>
    SVG
      result = Lithop::ImagePipeline.new(settings).call(path)

      expect(result.cmys).to all(eq([0.0, 0.0, 0.0]))
      expect(result.cmy_densities).to all(eq(0.0))
    end
  end

  it "allows document-local fragment references" do
    with_svg("internal.svg", <<~SVG) do |path|
      <svg xmlns="http://www.w3.org/2000/svg" width="3px" height="2px">
        <defs><rect id="cyan" width="3" height="2" fill="#00ffff"/></defs>
        <use href="#cyan"/>
      </svg>
    SVG
      result = Lithop::ImagePipeline.new(settings).call(path)

      expect(result.cmys).to all(eq([1.0, 0.0, 0.0]))
    end
  end

  it "renders gradients, clipping, masks, and transforms" do
    with_svg("decorated.svg", <<~SVG) do |path|
      <svg xmlns="http://www.w3.org/2000/svg" width="3" height="2" viewBox="0 0 3 2">
        <defs>
          <linearGradient id="gradient"><stop stop-color="#00ffff"/><stop offset="1" stop-color="#fff"/></linearGradient>
          <clipPath id="clip"><rect width="3" height="2"/></clipPath>
          <mask id="mask"><rect width="3" height="2" fill="#fff"/></mask>
        </defs>
        <g transform="translate(0 0)" clip-path="url(#clip)" mask="url(#mask)">
          <rect width="3" height="2" fill="url(#gradient)"/>
        </g>
      </svg>
    SVG
      result = Lithop::ImagePipeline.new(settings).call(path)

      expect([result.width, result.height]).to eq([3, 2])
      expect(result.cmy_densities).to all(be_between(0.0, 1.0))
    end
  end

  it "rejects external, data, and CSS references before rendering" do
    references = [
      '<image href="other.png"/>',
      '<image href="data:image/png;base64,AA=="/>',
      "<style>.sample { fill: url(https://example.invalid/color.svg#cyan); }</style>",
      "<style>.sample { fill: u/**/rl(https://example.invalid/color.svg#cyan); }</style>",
      '<style>.sample { fill: u\72 l(https://example.invalid/color.svg#cyan); }</style>',
      '<style>@import "theme.css";</style>'
    ]

    references.each_with_index do |reference, index|
      with_svg("reference-#{index}.svg", svg_with(reference)) do |path|
        expect { Lithop::ImagePipeline.new(settings).call(path) }
          .to raise_error(Lithop::InputError, /external|data|CSS/)
      end
    end
  end

  it "rejects active content, DTDs, and ambiguous dimensions" do
    invalid_inputs = {
      "script.svg" => svg_with('<script type="application/ecmascript">alert(1)</script>'),
      "doctype.svg" => '<!DOCTYPE svg><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"/>',
      "percentage.svg" => '<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="100%"/>'
    }

    invalid_inputs.each do |name, source|
      with_svg(name, source) do |path|
        expect { Lithop::ImagePipeline.new(settings).call(path) }.to raise_error(Lithop::InputError)
      end
    end
  end

  it "rejects SVGZ and formats outside the JPEG, PNG, and SVG allowlist" do
    Dir.mktmpdir do |directory|
      svgz = File.join(directory, "input.svgz")
      gif = File.join(directory, "input.gif")
      File.binwrite(svgz, "\x1F\x8Bcompressed".b)
      File.binwrite(gif, "GIF89a".b)

      expect { Lithop::ImagePipeline.new(settings).call(svgz) }
        .to raise_error(Lithop::InputError, /SVGZ/)
      expect { Lithop::ImagePipeline.new(settings).call(gif) }
        .to raise_error(Lithop::InputError, /JPEG, PNG, or SVG|invalid SVG XML/)
    end
  end

  it "checks the planned SVG raster size before the full render" do
    limited = Lithop::Settings.new(width: 2.0, height: 1.0, pixel_size: 1.0, maximum_input_pixels: 5)

    with_svg("large-render.svg", svg_with('<rect width="1" height="1" fill="#fff"/>')) do |path|
      expect { Lithop::ImagePipeline.new(limited).call(path) }
        .to raise_error(Lithop::InputError, /SVG rasterization would exceed 5 pixels/)
    end
  end

  it "applies the pixel limit to the scaled render instead of intrinsic SVG units" do
    limited = Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0, maximum_input_pixels: 4)
    source = <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="100000px" height="100000px" viewBox="0 0 1 1">
        <rect width="1" height="1" fill="#00ffff"/>
      </svg>
    SVG

    with_svg("large-units.svg", source) do |path|
      result = Lithop::ImagePipeline.new(limited).call(path)

      expect([result.width, result.height]).to eq([2, 2])
    end
  end

  it "enforces the SVG byte limit" do
    expect(Lithop::SVGLoader::MAXIMUM_FILE_BYTES).to eq(15_000_000)

    stub_const("Lithop::SVGLoader::MAXIMUM_FILE_BYTES", 100)
    oversized = svg_with("<!-- #{"x" * 100} -->")

    with_svg("oversized.svg", oversized) do |path|
      expect { Lithop::ImagePipeline.new(settings).call(path) }
        .to raise_error(Lithop::InputError, /exceeds 100 bytes/)
    end
  end

  it "reports a missing SVG loader" do
    with_svg("loader.svg", svg_with('<rect width="1" height="1"/>')) do |path|
      allow(Vips::Operation).to receive(:new).with("svgload_buffer").and_raise(Vips::Error.new("missing"))

      expect { Lithop::ImagePipeline.new(settings).call(path) }
        .to raise_error(Lithop::InputError, /libvips with librsvg support/)
    end
  end

  it "maps the bundled CMY chart to seven-layer recipes" do
    chart_settings = Lithop::Settings.new(width: 140.0, height: 104.0, pixel_size: 1.0)
    result = Lithop::ImagePipeline.new(chart_settings).call("examples/cmy-color-chart.svg")
    palette = Lithop::Palette.new
    x_positions = [6.5, 15.8, 25.1, 34.4, 43.7, 53.0, 62.3, 71.6, 80.9, 90.2, 99.5, 108.8, 118.1]
                  .map { |position| position * 140.0 / 130.0 }
    density_rows = [
      [17.25, 0.0], [24.25, 0.05], [31.25, 0.1], [38.25, 0.2], [45.25, 0.3], [52.25, 0.4],
      [59.25, 0.5], [66.25, 0.6], [73.25, 0.7], [80.25, 0.8], [87.25, 0.9], [94.25, 1.0]
    ].map { |position, density| [position * 104.0 / 100.0, density] }
    recipes = density_rows.drop(1).map do |y_position, _density|
      sample_y = chart_coordinate(y_position, 104.0, result.height)
      x_positions.map do |x_position|
        sample_x = chart_coordinate(x_position, 140.0, result.width)
        palette.nearest(result.cmys.fetch((sample_y * result.width) + sample_x)).layers
      end
    end

    expected_recipes = [
      %i[cyan cyan cyan magenta magenta magenta magenta],
      %i[cyan cyan cyan magenta magenta magenta magenta],
      %i[cyan cyan cyan cyan magenta magenta magenta],
      %i[cyan cyan cyan cyan cyan cyan cyan],
      %i[cyan cyan cyan cyan yellow yellow yellow],
      %i[cyan cyan cyan yellow yellow yellow yellow],
      %i[cyan cyan cyan yellow yellow yellow yellow],
      %i[yellow yellow yellow yellow yellow yellow yellow],
      %i[magenta magenta magenta yellow yellow yellow yellow],
      %i[magenta magenta magenta yellow yellow yellow yellow],
      %i[magenta magenta magenta magenta yellow yellow yellow],
      %i[magenta magenta magenta magenta magenta magenta magenta],
      %i[cyan magenta magenta magenta yellow yellow yellow]
    ]
    expect(recipes).to all(eq(expected_recipes))

    cyan_x = chart_coordinate(34.4 * 140.0 / 130.0, 140.0, result.width)
    densities = density_rows.map do |y_position, _density|
      sample_y = chart_coordinate(y_position, 104.0, result.height)
      result.cmy_densities.fetch((sample_y * result.width) + cyan_x)
    end
    expect(densities).to match(density_rows.map { |_position, density| be_within(0.01).of(density) })

    density_rows.each do |y_position, expected_density|
      sample_y = chart_coordinate(y_position, 104.0, result.height)
      white_densities = x_positions.map do |x_position|
        sample_x = chart_coordinate(x_position, 140.0, result.width)
        result.white_densities.fetch((sample_y * result.width) + sample_x)
      end
      expect(white_densities).to all(be_within(0.01).of(expected_density))
    end

    zero_y = chart_coordinate(17.25 * 104.0 / 100.0, 104.0, result.height)
    zero_cmy = result.cmys.fetch((zero_y * result.width) + cyan_x)
    expect(palette.nearest(zero_cmy).layers).to eq([:white] * 7)
  end

  it "preserves every CMY chart column at five-percent brightness" do
    chart_settings = Lithop::Settings.new(width: 140.0, height: 104.0, pixel_size: 1.0)
    result = Lithop::ImagePipeline.new(chart_settings).call("examples/cmy-color-chart.svg")
    x_positions = [6.5, 15.8, 25.1, 34.4, 43.7, 53.0, 62.3, 71.6, 80.9, 90.2, 99.5, 108.8, 118.1]
                  .map { |position| position * 140.0 / 130.0 }
    row = chart_coordinate(24.25 * 104.0 / 100.0, 104.0, result.height).clamp(0, chart_settings.rows - 1)

    recipes = x_positions.map do |x_position|
      column = chart_coordinate(x_position, 140.0, result.width).clamp(0, chart_settings.columns - 1)
      Lithop::Palette.new.nearest(result.color_cells.fetch((row * chart_settings.columns) + column))
    end

    expect(recipes).to all(satisfy { |recipe| recipe.pigments.any? })
  end

  def with_svg(name, source)
    Dir.mktmpdir do |directory|
      path = File.join(directory, name)
      File.write(path, source)
      yield path
    end
  end

  def svg_with(content)
    <<~SVG
      <svg xmlns="http://www.w3.org/2000/svg" width="1px" height="1px" viewBox="0 0 1 1">
        #{content}
      </svg>
    SVG
  end

  def chart_coordinate(value, source_extent, output_extent)
    (value.fdiv(source_extent) * (output_extent - 1)).round
  end
end

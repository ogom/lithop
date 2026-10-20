# frozen_string_literal: true

module Lithop
  # Loads, normalizes, and samples an input image for model generation.
  # rubocop:disable-next Metrics/ClassLength
  class ImagePipeline
    REFERENCE_WHITE_MAXIMUM_DENSITY = 0.04
    REFERENCE_WHITE_MAXIMUM_CHROMA = 0.08
    REFERENCE_DARK_MAXIMUM_VALUE = 0.75
    REFERENCE_NEUTRAL_MAXIMUM_CHROMA = 0.25
    REFERENCE_BROWN_LINE_CMY_COVERAGE = 1.0 / 7
    Result = Data.define(
      :width, :height, :cmys, :cmy_densities, :white_densities, :color_cells, :corrected_preview_png
    )

    def initialize(settings)
      @settings = settings
      @placement = ImagePlacement.new(settings)
      @svg_loader = SVGLoader.new(settings)
    end

    def call(path)
      require "vips"

      access = @settings.color_pixel_size ? :random : :sequential
      image = normalized_image(path, access:)
      sampled = @placement.call(image, @settings.sampling_grid).cast(:uchar).copy_memory

      rgbs = rgb_components(sampled)
      color_samples = rgbs.map { |rgb| color_sample(rgb) }
      result_color_cells = if @settings.color_pixel_size
                             color_cells(image)
                           else
                             standard_color_cells(color_samples, @settings.columns, @settings.rows)
                           end
      Result.new(
        width: sampled.width,
        height: sampled.height,
        cmys: color_samples.map(&:first),
        cmy_densities: color_samples.map(&:last),
        white_densities: rgbs.map { |rgb| white_density(rgb) },
        color_cells: result_color_cells,
        corrected_preview_png: sampled.write_to_buffer(".png")
      )
    rescue SystemCallError, Vips::Error => e
      raise InputError, "could not read image: #{e.message}"
    end

    # Returns the same normalized and placed image used by conversion, bounded
    # to a browser-friendly sampling grid and without running CMYW or mesh work.
    def preview_png(path, maximum_width: 960, maximum_height: 720)
      require "vips"

      grid = preview_grid(maximum_width:, maximum_height:)
      image = normalized_image(path, access: :sequential, sampling_grids: [grid])
      @placement.call(image, grid).cast(:uchar).write_to_buffer(".png")
    rescue SystemCallError, Vips::Error => e
      raise InputError, "could not read image: #{e.message}"
    end

    private

    def normalized_image(path, access:, sampling_grids: nil)
      image = load_image(path, access:, sampling_grids:)
      image = image.autorot
      validate_input!(image)
      image = image.flatten(background: [255, 255, 255]) if image.has_alpha?
      adjust_image(to_srgb(image))
    end

    def load_image(path, access:, sampling_grids: nil)
      signature = File.binread(path, 8)
      raster = signature.start_with?("\xFF\xD8\xFF".b) || signature.start_with?("\x89PNG\r\n\x1A\n".b)
      return Vips::Image.new_from_file(path.to_s, access:) if raster

      @svg_loader.call(path, access:, sampling_grids:)
    end

    def preview_grid(maximum_width:, maximum_height:)
      maximum_width = Integer(maximum_width)
      maximum_height = Integer(maximum_height)
      raise InputError, "preview dimensions must be at least 2 pixels" if maximum_width < 2 || maximum_height < 2

      pixel_size = [
        @settings.width.fdiv(maximum_width - 1),
        @settings.height.fdiv(maximum_height - 1),
        0.01
      ].max
      SamplingGrid.new(
        width: @settings.width, height: @settings.height, pixel_size:,
        margins: {
          top: @settings.margin_top, right: @settings.margin_right,
          bottom: @settings.margin_bottom, left: @settings.margin_left
        }
      )
    rescue ArgumentError, TypeError
      raise InputError, "preview dimensions must be integers"
    end

    def validate_input!(image)
      unless %w[jpegload pngload svgload_buffer].include?(image.get("vips-loader"))
        raise InputError, "input must be a JPEG, PNG, or SVG image"
      end
      return unless image.width * image.height > @settings.maximum_input_pixels

      raise InputError, "input image exceeds #{@settings.maximum_input_pixels} pixels"
    end

    def to_srgb(image)
      return image.colourspace(:srgb) if image.get_typeof("icc-profile-data").zero?

      image.icc_import(embedded: true, pcs: :xyz).colourspace(:srgb)
    end

    def adjust_image(image)
      return image if image_adjustments.none?(&:nonzero?)

      adjusted = image.cast(:float)
      adjusted += @settings.brightness.fdiv(100) * 255
      contrast_factor = 1.0 + @settings.contrast.fdiv(100)
      adjusted = ((adjusted - 127.5) * contrast_factor) + 127.5
      saturation_factor = 1.0 + @settings.saturation.fdiv(100)
      luminance = (adjusted[0] * 0.299) + (adjusted[1] * 0.587) + (adjusted[2] * 0.114)
      luminance + ((adjusted - luminance) * saturation_factor)
    end

    def image_adjustments
      [@settings.brightness, @settings.contrast, @settings.saturation]
    end

    def color_cells(image)
      return if @settings.color_pixel_size.nil?

      grid = @settings.color_sampling_grid
      sampled = @placement.call(image, grid).cast(:uchar)
      samples = rgb_components(sampled).map { |rgb| color_sample(rgb) }
      coarse_cells = standard_color_cells(samples, grid.columns, grid.rows)
      expand_color_cells(coarse_cells, grid)
    end

    def standard_color_cells(color_samples, columns, rows)
      stride = columns + 1
      Array.new(rows * columns) do |index|
        row, column = index.divmod(columns)
        top_left = (row * stride) + column
        samples = [
          color_samples.fetch(top_left), color_samples.fetch(top_left + 1),
          color_samples.fetch(top_left + stride), color_samples.fetch(top_left + stride + 1)
        ]
        if samples.any? { |sample| standard_brown_line_sample?(sample.first) }
          next Array.new(3, REFERENCE_BROWN_LINE_CMY_COVERAGE)
        end

        density = samples.sum(&:last).fdiv(samples.length)
        cmy = samples.map(&:first).transpose.map { |components| components.sum.fdiv(components.length) }
        next [0.0, 0.0, 0.0] if standard_white?(density, cmy)

        cmy
      end
    end

    def expand_color_cells(coarse_cells, grid)
      Array.new(@settings.rows * @settings.columns) do |index|
        row, column = index.divmod(@settings.columns)
        x = cell_center(@settings.x_boundaries, column)
        y = cell_center(@settings.y_boundaries, row)
        coarse_column = containing_cell(grid.x_boundaries, x)
        coarse_row = containing_cell(grid.y_boundaries, y)
        coarse_cells.fetch((coarse_row * grid.columns) + coarse_column)
      end
    end

    def cell_center(boundaries, index)
      (boundaries.fetch(index) + boundaries.fetch(index + 1)).fdiv(2)
    end

    def containing_cell(boundaries, coordinate)
      upper = boundaries.bsearch_index { |boundary| boundary > coordinate } || (boundaries.length - 1)
      (upper - 1).clamp(0, boundaries.length - 2)
    end

    def rgb_components(image)
      pixels = image.write_to_memory
      bands = image.bands
      count = image.width * image.height

      Array.new(count) do |index|
        offset = index * bands
        3.times.map { |band| pixels.getbyte(offset + band).fdiv(255) }
      end
    end

    def color_sample(rgb)
      display_sample = FilamentProfile.display_sample(rgb)
      return [display_sample.cmy, display_sample.density] if display_sample

      maximum = rgb.max
      cmy = standard_cmy(rgb, maximum)
      density = rgb.sum { |component| 1.0 - component }.fdiv(3)
      [cmy, density]
    end

    def standard_cmy(rgb, maximum)
      chroma = rgb.map { |component| maximum - component }
      return chroma unless maximum <= REFERENCE_DARK_MAXIMUM_VALUE &&
                           chroma.max <= REFERENCE_NEUTRAL_MAXIMUM_CHROMA

      Array.new(3, REFERENCE_BROWN_LINE_CMY_COVERAGE)
    end

    def standard_brown_line_sample?(cmy)
      cmy.all? { |component| (component - REFERENCE_BROWN_LINE_CMY_COVERAGE).abs < 1e-12 }
    end

    def standard_white?(density, cmy)
      return false if density > REFERENCE_WHITE_MAXIMUM_DENSITY

      pale_yellow = cmy.fetch(2) == cmy.max && cmy.fetch(2) > REFERENCE_WHITE_MAXIMUM_CHROMA &&
                    cmy.fetch(0) <= 0.05
      !pale_yellow
    end

    def rec601_density(rgb)
      1.0 - rgb.zip([0.299, 0.587, 0.114]).sum { |component, weight| component * weight }
    end

    def white_density(rgb)
      FilamentProfile.display_sample(rgb)&.density || rec601_density(rgb)
    end
  end
end

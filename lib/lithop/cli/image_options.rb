# frozen_string_literal: true

module Lithop
  # Adds dimensions, image placement, thickness, and sampling options.
  module CLIImageOptions
    module_function

    def add(parser, options)
      add_dimensions(parser, options)
      add_tiles(parser, options)
      add_margins(parser, options)
      add_placement(parser, options)
      CLIImageAdjustmentOptions.add(parser, options)
      add_thickness(parser, options)
      add_sampling(parser, options)
    end

    def add_dimensions(parser, options)
      parser.on("--layout-profile NAME", "Layout profile: standard") do |value|
        options[:layout_profile] = value
      end
      parser.on("--width MM", Float, "Model width (default: #{Settings::DEFAULTS.fetch(:width)})") do |value|
        options[:width] = value
      end
      parser.on("--height MM", Float, "Model height (default: #{Settings::DEFAULTS.fetch(:height)})") do |value|
        options[:height] = value
      end
    end
    private_class_method :add_dimensions

    def add_tiles(parser, options)
      parser.on("--tile-count COUNT", Integer, "Number of 3MF tiles (default: 1)") do |value|
        options[:tile_count] = value
      end
      parser.on("--tile-layout MODE", "Tile layout: auto/columns/rows/grid (default: auto)") do |value|
        options[:tile_layout] = value.downcase
      end
      parser.on("--tile-rows COUNT", Integer, "Tile rows for grid layout") { |value| options[:tile_rows] = value }
      parser.on("--tile-columns COUNT", Integer, "Tile columns for grid layout") do |value|
        options[:tile_columns] = value
      end
      parser.on("--separate-z-parts", "Slice the complete model into contiguous Z plates") do
        options[:separate_z_parts] = true
      end
      parser.on("--color-region-parts COUNT", Integer, "Z plate count (1-3); thinnest plate is 0.34 mm") do |value|
        options[:color_region_parts] = value
      end
    end
    private_class_method :add_tiles

    def add_margins(parser, options)
      parser.on("--margin-top MM", Float, "Top margin (default: 0)") { |value| options[:margin_top] = value }
      parser.on("--margin-right MM", Float, "Right margin (default: 0)") { |value| options[:margin_right] = value }
      parser.on("--margin-bottom MM", Float, "Bottom margin (default: 0)") { |value| options[:margin_bottom] = value }
      parser.on("--margin-left MM", Float, "Left margin (default: 0)") { |value| options[:margin_left] = value }
    end
    private_class_method :add_margins

    def add_placement(parser, options)
      parser.on("--image-fit MODE", "Image fit: cover/contain (default: cover)") do |value|
        options[:image_fit] = value.downcase
      end
      parser.on("--crop-position-x FRACTION", Float, "Horizontal image position: 0..1 (default: 0.5)") do |value|
        options[:crop_position_x] = value
      end
      parser.on("--crop-position-y FRACTION", Float, "Vertical image position: 0..1 (default: 0.5)") do |value|
        options[:crop_position_y] = value
      end
      parser.on("--crop-scale FRACTION", Float, "Crop rectangle scale: >0..1 (default: 1)") do |value|
        options[:crop_scale] = value
      end
    end
    private_class_method :add_placement

    def add_thickness(parser, options)
      parser.on("--min-thickness MM", Float, "Requested minimum model thickness (default: 0.74)") do |value|
        options[:minimum_thickness] = value
      end
      parser.on("--max-thickness MM", Float, "Requested maximum model thickness (default: 1.94)") do |value|
        options[:maximum_thickness] = value
      end
    end
    private_class_method :add_thickness

    def add_sampling(parser, options)
      parser.on("--pixel-size MM", Float, "XY pixel size (default: 0.22)") do |value|
        options[:pixel_size] = value
      end
      parser.on("--color-pixel-size MM", Float, "Color-cell size >= pixel size (default: pixel size)") do |value|
        options[:color_pixel_size] = value
      end
    end
    private_class_method :add_sampling
  end
end

# frozen_string_literal: true

module Lithop
  # Validates the user-supplied generation settings.
  # rubocop:disable-next Metrics/ModuleLength
  module SettingsValidation
    private

    def validate!
      validate_positive_values!
      validate_thickness_range!
      validate_output_limits!
      validate_color_model!
      validate_layout_profile!
      validate_grid!
      validate_layer_structure!
      validate_advanced_layer_structure!
      validate_margins!
      validate_image_placement!
      validate_nozzle_diameter!
      validate_mesh_limit!
    end

    def validate_positive_values!
      %i[width height minimum_thickness maximum_thickness pixel_size first_layer_height layer_height].each do |key|
        value = public_send(key)
        next if value.is_a?(Numeric) && value.finite? && value.positive?

        raise ConfigurationError, "#{key} must be a positive finite number"
      end
      return if color_pixel_size.nil?
      unless color_pixel_size.is_a?(Numeric) && color_pixel_size.finite? && color_pixel_size.positive?
        raise ConfigurationError, "color_pixel_size must be a positive finite number or null"
      end
      return if color_pixel_size >= pixel_size

      raise ConfigurationError, "color_pixel_size must be greater than or equal to pixel_size"
    end

    def validate_thickness_range!
      return unless minimum_thickness > maximum_thickness

      raise ConfigurationError, "minimum_thickness must not exceed maximum_thickness"
    end

    def validate_output_limits!
      %i[maximum_input_pixels maximum_triangles].each do |key|
        value = public_send(key)
        next if value.is_a?(Integer) && value.positive?

        raise ConfigurationError, "#{key} must be a positive integer"
      end
    end

    def validate_color_model!
      return if Settings::COLOR_MODELS.include?(color_model)

      raise ConfigurationError, "color_model must be one of: cmy"
    end

    def validate_layout_profile!
      return if Settings::LAYOUT_PROFILES.include?(layout_profile)

      raise ConfigurationError, "layout_profile must be one of: #{Settings::LAYOUT_PROFILES.join(", ")}"
    end

    def validate_grid!
      raise ConfigurationError, "grid_columns and grid_rows must be set together" if grid_columns.nil? ^ grid_rows.nil?
      return if grid_columns.nil?
      return if grid_columns.is_a?(Integer) && grid_columns.positive? &&
                grid_rows.is_a?(Integer) && grid_rows.positive?

      raise ConfigurationError, "grid_columns and grid_rows must be positive integers or null"
    end

    def validate_layer_structure!
      return if Settings::COLOR_LAYER_COUNTS.include?(color_layer_count)

      raise ConfigurationError, "color_layer_count must be one of: #{Settings::COLOR_LAYER_COUNTS.join(", ")}"
    end

    # rubocop:disable-next Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def validate_advanced_layer_structure!
      unless base_white_layers.is_a?(Integer) && base_white_layers.positive?
        raise ConfigurationError, "base_white_layers must be a positive integer"
      end
      unless minimum_top_white_layers.is_a?(Integer) && minimum_top_white_layers >= 0
        raise ConfigurationError, "minimum_top_white_layers must be a non-negative integer"
      end
      unless top_layer_height.nil? ||
             (top_layer_height.is_a?(Numeric) && top_layer_height.finite? && top_layer_height.positive?)
        raise ConfigurationError, "top_layer_height must be a positive finite number or null"
      end
      if !top_white_start.nil? &&
         (!top_white_start.is_a?(Numeric) || !top_white_start.finite? || !top_white_start.positive?)
        raise ConfigurationError, "top_white_start must be a positive finite number or null"
      end
      return if [true, false].include?(exact_maximum_thickness) && [true, false].include?(bambu_project)

      raise ConfigurationError, "exact_maximum_thickness and bambu_project must be booleans"
    end

    def validate_margins!
      %i[margin_top margin_right margin_bottom margin_left].each do |key|
        value = public_send(key)
        next if value.is_a?(Numeric) && value.finite? && value >= 0.0

        raise ConfigurationError, "#{key} must be a non-negative finite number"
      end
      return if margin_left + margin_right < width && margin_top + margin_bottom < height

      raise ConfigurationError, "horizontal and vertical margins must each leave image area"
    end

    def validate_image_placement!
      unless Settings::IMAGE_FITS.include?(image_fit)
        raise ConfigurationError, "image_fit must be one of: #{Settings::IMAGE_FITS.join(", ")}"
      end

      %i[crop_position_x crop_position_y].each do |key|
        value = public_send(key)
        next if value.is_a?(Numeric) && value.finite? && value.between?(0.0, 1.0)

        raise ConfigurationError, "#{key} must be a finite number from 0 to 1"
      end
      return if crop_scale.is_a?(Numeric) && crop_scale.finite? && crop_scale.positive? && crop_scale <= 1.0

      raise ConfigurationError, "crop_scale must be a finite number greater than 0 and at most 1"
    end

    def validate_nozzle_diameter!
      return if Settings::NOZZLE_DIAMETERS.include?(nozzle_diameter)

      raise ConfigurationError, "nozzle_diameter must be one of: 0.2, 0.4"
    end

    def validate_mesh_limit!
      return unless estimated_triangles > maximum_triangles

      raise ConfigurationError, triangle_limit_message("estimated STL mesh", estimated_triangles)
    end

    def normalize_pigment_order(value)
      entries = value.is_a?(String) ? value.split(",") : value
      raise ConfigurationError, "pigment_order must be a comma-separated string or an array" unless entries.is_a?(Array)

      order = entries.map { |entry| entry.to_s.strip.downcase.to_sym }
      return order.freeze if order.length == Settings::PIGMENTS.length && order.sort == Settings::PIGMENTS.sort

      raise ConfigurationError, "pigment_order must contain cyan, magenta, and yellow exactly once"
    end

    def validate_physical_minimum!
      return if effective_minimum_thickness >= minimum_physical_thickness

      raise ConfigurationError,
            "physical CMYW output requires at least #{minimum_physical_thickness} mm thickness; " \
            "set --min-thickness accordingly"
    end

    def minimum_physical_thickness
      layer_structure.minimum_physical_thickness
    end
  end

  # Validated dimensions, print parameters, and output limits for a generation job.
  # rubocop:disable-next Metrics/ClassLength
  class Settings
    include SettingsValidation

    MICRONS_PER_MM = LayerStructure::MICRONS_PER_MM
    COLOR_MODELS = %w[cmy].freeze
    NOZZLE_DIAMETERS = [0.2, 0.4].freeze
    COLOR_LAYER_COUNTS = [4, 5, 7].freeze
    LAYOUT_PROFILES = ["standard"].freeze
    IMAGE_FITS = %w[cover contain].freeze
    PIGMENTS = %i[cyan magenta yellow].freeze
    MINIMUM_TOP_WHITE_LAYERS = LayerStructure::MINIMUM_TOP_WHITE_LAYERS
    DEFAULTS = {
      layout_profile: "standard",
      width: 140.0,
      height: 104.0,
      margin_top: 0.0,
      margin_right: 0.0,
      margin_bottom: 0.0,
      margin_left: 0.0,
      image_fit: "cover",
      crop_position_x: 0.5,
      crop_position_y: 0.5,
      crop_scale: 1.0,
      minimum_thickness: 1.0,
      maximum_thickness: 2.14689422,
      pixel_size: 0.22,
      color_pixel_size: nil,
      grid_columns: 637,
      grid_rows: 473,
      first_layer_height: 0.1,
      layer_height: 0.1,
      base_white_layers: 2,
      top_layer_height: 0.04,
      top_white_start: 1.0,
      minimum_top_white_layers: 0,
      exact_maximum_thickness: true,
      nozzle_diameter: 0.2,
      color_model: "cmy",
      color_layer_count: 7,
      pigment_order: PIGMENTS,
      bambu_project: true,
      maximum_input_pixels: 20_000_000,
      maximum_triangles: 5_000_000
    }.freeze
    attr_reader(
      *DEFAULTS.keys, :effective_minimum_thickness, :effective_maximum_thickness, :layer_structure
    )

    def initialize(**values)
      profile = values.fetch(:layout_profile, DEFAULTS.fetch(:layout_profile)).to_s
      values = without_default_grid(values)
      settings = DEFAULTS.merge(values).merge(layout_profile: profile)
      DEFAULTS.each_key { |key| instance_variable_set("@#{key}", settings.fetch(key)) }
      @pigment_order = normalize_pigment_order(@pigment_order)
      validate!
      @layer_structure = LayerStructure.new(
        first_layer_height:, layer_height:, color_layer_count:, minimum_thickness:, maximum_thickness:,
        base_white_layers:, top_layer_height:, top_white_start:, minimum_top_white_layers:,
        exact_maximum_thickness:
      )
      @effective_minimum_thickness = layer_structure.effective_minimum_thickness
      @effective_maximum_thickness = layer_structure.effective_maximum_thickness
      if effective_minimum_thickness > effective_maximum_thickness
        raise ConfigurationError, "the requested thickness range contains no printable layer boundary"
      end

      validate_physical_minimum!
    end

    def without_default_grid(values)
      dimensions = %i[width height pixel_size]
      explicit_grid = values.key?(:grid_columns) || values.key?(:grid_rows)
      return values if explicit_grid || dimensions.none? { |key| values.key?(key) }

      values.merge(grid_columns: nil, grid_rows: nil)
    end
    private :without_default_grid

    def columns = sampling_grid.columns
    def rows = sampling_grid.rows
    def effective_color_pixel_size = color_pixel_size || pixel_size
    def fitted_grid? = !grid_columns.nil?
    def pixel_size_x = width.fdiv(columns)
    def pixel_size_y = height.fdiv(rows)

    def estimated_triangles
      (4 * columns * rows) + (4 * (columns + rows))
    end

    def triangle_limit_message(label, triangle_count)
      scale = Math.sqrt(triangle_count.fdiv(maximum_triangles))
      suggested_pixel_size = ((pixel_size * scale * 100).ceil / 100.0).round(2)
      "#{label} has #{triangle_count} triangles; maximum is #{maximum_triangles}. " \
        "Increase pixel_size to about #{suggested_pixel_size} mm or reduce width/height"
    end

    def x_boundaries = sampling_grid.x_boundaries
    def y_boundaries = sampling_grid.y_boundaries
    def quantize_thickness(value) = layer_structure.quantize_thickness(value)
    def margin_samples = sampling_grid.margin_samples

    def sampling_grid
      @sampling_grid ||= SamplingGrid.new(
        width:, height:, pixel_size:,
        margins: { top: margin_top, right: margin_right, bottom: margin_bottom, left: margin_left },
        columns: grid_columns, rows: grid_rows
      )
    end

    def color_sampling_grid
      return sampling_grid if color_pixel_size.nil?

      @color_sampling_grid ||= SamplingGrid.new(
        width:, height:, pixel_size: effective_color_pixel_size,
        margins: { top: margin_top, right: margin_right, bottom: margin_bottom, left: margin_left }
      )
    end

    def to_h
      DEFAULTS.keys.to_h { |key| [key, public_send(key)] }.merge(
        effective_color_pixel_size: effective_color_pixel_size,
        effective_minimum_thickness: effective_minimum_thickness,
        effective_maximum_thickness: effective_maximum_thickness,
        columns: columns, rows: rows, pixel_size_x: pixel_size_x, pixel_size_y: pixel_size_y
      )
    end
  end
end

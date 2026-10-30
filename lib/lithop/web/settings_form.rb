# frozen_string_literal: true

module Lithop
  module Web
    # Resolves browser form values through the same Settings validation used by the CLI.
    class SettingsForm
      FLOAT_FIELDS = %i[
        width height margin_top margin_right margin_bottom margin_left crop_position_x crop_position_y
        crop_scale brightness contrast saturation yellow_mix_percent minimum_thickness maximum_thickness pixel_size
        color_pixel_size nozzle_diameter
      ].freeze
      INTEGER_FIELDS = %i[tile_count tile_rows tile_columns color_region_parts].freeze
      STRING_FIELDS = %i[image_fit tile_layout yellow_mix_color pigment_order].freeze
      BOOLEAN_FIELDS = %i[suppress_pale_colors separate_z_parts].freeze
      FIELD_NAMES = (FLOAT_FIELDS + INTEGER_FIELDS + STRING_FIELDS + BOOLEAN_FIELDS).map(&:to_s).freeze

      attr_reader :defaults

      def initialize(project_dir:)
        @project_dir = File.expand_path(project_dir)
        @file_settings = SettingsFile.load(File.join(@project_dir, SettingsFile::DEFAULT_PATH)).values
        @defaults = Settings.new(**@file_settings)
      end

      def resolve(params)
        overrides = parse_fields(params)
        Settings.new(**@file_settings, **overrides)
      end

      def values(settings = defaults)
        result = settings.to_h.slice(*Settings::DEFAULTS.keys).transform_keys(&:to_s)
        result["pigment_order"] = settings.pigment_order.join(",")
        result
      end

      private

      def parse_fields(params)
        values = {}
        FLOAT_FIELDS.each { |key| assign_number(values, params, key, Float) }
        INTEGER_FIELDS.each { |key| assign_number(values, params, key, Integer) }
        STRING_FIELDS.each { |key| values[key] = params[key.to_s] if present?(params[key.to_s]) }
        BOOLEAN_FIELDS.each { |key| values[key] = params[key.to_s] == "1" }
        clear_unused_grid(values)
        values
      rescue ArgumentError
        raise ConfigurationError, "settings must contain valid numbers"
      end

      def assign_number(values, params, key, converter)
        value = params[key.to_s]
        return unless present?(value)

        values[key] = converter == Integer ? Integer(value, 10) : Float(value)
      end

      def clear_unused_grid(values)
        return if values.fetch(:tile_layout, defaults.tile_layout) == "grid"

        values[:tile_rows] = nil
        values[:tile_columns] = nil
      end

      def present?(value) = !value.nil? && !value.to_s.strip.empty?
    end
  end
end

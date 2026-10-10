# frozen_string_literal: true

module Lithop
  module Calibration
    # Selects a printable recipe from measured transmitted colors.
    class RecipeSelector
      attr_reader :layer_count, :pigment_order, :recipes

      def initialize(profile:, palette:)
        profile.validate_complete!
        @layer_count = palette.layer_count
        @pigment_order = palette.pigment_order
        @recipes = palette.recipes
        @entries = build_entries(profile.measurements(:recipe))
      end

      def nearest(cmy)
        validate_cmy!(cmy)
        target = cmy.map { |component| 1.0 - component }
        @entries.min_by do |_recipe, measured|
          measured.zip(target).sum { |component, expected| (component - expected)**2 }
        end.first
      end

      private

      def build_entries(measurements)
        measurements.map do |measurement|
          recipe = recipes.find { |candidate| recipe_counts(candidate) == measurement.recipe }
          raise InputError, "calibration profile contains an unknown recipe" unless recipe

          [recipe, normalize(measurement.transmitted_srgb)]
        end
      end

      def recipe_counts(recipe)
        recipe.to_h.fetch(:counts).transform_keys(&:to_s)
      end

      def normalize(rgb)
        maximum = rgb.max
        return [0.0, 0.0, 0.0] if maximum.zero?

        rgb.map { |component| component.fdiv(maximum) }
      end

      def validate_cmy!(cmy)
        valid = cmy.is_a?(Array) && cmy.length == 3 &&
                cmy.all? { |value| value.is_a?(Numeric) && value.finite? && value.between?(0.0, 1.0) }
        raise InputError, "CMY must contain three values between 0 and 1" unless valid
      end
    end
  end
end

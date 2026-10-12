# frozen_string_literal: true

module Lithop
  module Calibration
    # Maps White display density to the closest measured White thickness stage.
    class ThicknessSelector
      def initialize(profile:, settings:)
        profile.validate_complete!
        @settings = settings
        @stages = profile.measurements(:white_thickness)
        @brightest = @stages.map(&:luminance).max
        @darkest = @stages.map(&:luminance).min
        return unless @brightest == @darkest

        raise InputError, "calibration White thickness measurements must span more than one luminance"
      end

      def call(densities)
        densities.map { |density| thickness_for(density) }
      end

      private

      def thickness_for(density)
        unless density.is_a?(Numeric) && density.finite? && density.between?(0.0, 1.0)
          raise InputError, "White density must be between 0 and 1"
        end

        target = @brightest - (density * (@brightest - @darkest))
        stage = @stages.min_by { |candidate| (candidate.luminance - target).abs }
        @settings.quantize_thickness(stage.height)
      end
    end
  end
end

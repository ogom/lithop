# frozen_string_literal: true

module Lithop
  # Converts image density values into printable, layer-aligned thicknesses.
  module Thickness
    module_function

    def from_cmy_density(densities, settings)
      validate_densities!(densities)
      densities = normalize_reference_densities(densities)
      minimum = settings.effective_minimum_thickness
      range = settings.effective_maximum_thickness - minimum

      densities.map do |density|
        unless density.is_a?(Numeric) && density.finite? && density.between?(0.0, 1.0)
          raise InputError, "CMY density must be between 0 and 1"
        end

        settings.quantize_thickness(minimum + (density * range))
      end
    end

    def continuous_from_density(densities, settings)
      validate_densities!(densities)
      normalized = normalize_reference_densities(densities)
      minimum = settings.effective_minimum_thickness
      range = settings.effective_maximum_thickness - minimum
      normalized.map { |density| minimum + (density * range) }
    end

    def validate_densities!(densities)
      return if densities.all? { |density| density.is_a?(Numeric) && density.finite? && density.between?(0.0, 1.0) }

      raise InputError, "CMY density must be between 0 and 1"
    end

    def normalize_reference_densities(densities)
      minimum, maximum = densities.minmax
      return Array.new(densities.length, 0.0) if maximum == minimum

      densities.map { |density| (density - minimum).fdiv(maximum - minimum) }
    end
    private_class_method :normalize_reference_densities, :validate_densities!
  end
end

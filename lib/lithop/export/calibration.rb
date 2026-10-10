# frozen_string_literal: true

module Lithop
  # Selects recipes and thicknesses for an optional measured calibration profile.
  class ExportCalibration
    attr_reader :profile, :path

    def initialize(settings:, input:)
      @settings = settings
      @profile = input&.profile
      @path = input&.path
    end

    def heights(densities)
      return Thickness.continuous_from_density(densities, @settings) unless profile

      Calibration::ThicknessSelector.new(profile:, settings: @settings).call(densities)
    end

    def palette
      palette = Palette.new(
        layer_count: @settings.color_layer_count,
        pigment_order: @settings.pigment_order
      )
      return palette unless profile

      Calibration::RecipeSelector.new(profile:, palette:)
    end

    def write(directory)
      profile&.write(File.join(directory, "calibration-profile.json"))
    end

    def metadata
      return "uncalibrated" unless profile

      {
        status: "measured",
        profile_id: profile.profile_id,
        source_path: path,
        recipe_method: "nearest_normalized_transmitted_srgb",
        thickness_method: "nearest_measured_white_luminance"
      }
    end
  end
end

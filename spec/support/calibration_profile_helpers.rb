# frozen_string_literal: true

module CalibrationProfileHelpers
  def measured_calibration_profile(settings, profile_id: "measured-001")
    target = Lithop::Calibration::Target.new(settings:)
    profile = Lithop::Calibration::Profile.template(profile_id:, settings:, target:)
    profile.data["status"] = "measured"
    profile.data.fetch("measurement")["white_point"] = measurement([1.0, 1.0, 1.0], 110.0)
    profile.data.fetch("measurement")["black_point"] = measurement([0.0, 0.0, 0.0], 0.0)
    profile.data.fetch("patches").each do |patch|
      patch.fetch("measurements") << measurement_for_patch(patch, settings)
    end
    yield profile if block_given?
    profile
  end

  private

  def measurement_for_patch(patch, settings)
    if patch.fetch("kind") == "recipe"
      counts = patch.fetch("recipe")
      rgb = %w[cyan magenta yellow].map do |channel|
        1.0 - counts.fetch(channel).fdiv(settings.color_layer_count)
      end
      measurement(rgb, 100.0)
    else
      minimum = settings.effective_minimum_thickness
      maximum = settings.effective_maximum_thickness
      ratio = (patch.fetch("total_thickness_mm") - minimum).fdiv(maximum - minimum)
      luminance = 100.0 - (ratio * 90.0)
      measurement([luminance / 100.0] * 3, luminance)
    end
  end

  def measurement(rgb, luminance)
    { "transmitted_srgb" => rgb, "luminance" => luminance, "error" => 0.5 }
  end
end

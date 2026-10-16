# frozen_string_literal: true

module Lithop
  # Writes print and material instructions for an exported project.
  module PrintReadme
    module_function

    def write(
      path, settings:, material_model:, tile_artifacts:, calibration_profile: nil,
      profile: FilamentProfile.default
    )
      materials = Palette::MATERIALS.select { |material| material_model.materials.include?(material) }
      names = materials.map { |material| profile_material(profile, material).name }
      assignments = materials.map do |material|
        "#{profile.materials.index(profile_material(profile, material)) + 1} #{material.to_s.capitalize}"
      end

      File.write(path, <<~MARKDOWN)
        # Lithop print guide

        This is #{calibration_profile ? "a measured-profile calibrated" : "an uncalibrated"} CMYW lithophane
        generated in millimetres.

        - #{model_instruction(tile_artifacts, names)}
        #{calibration_line(calibration_profile)}
        - Bambu Studio assignments encoded for this job: #{assignments.join(", ")}.
        - The model uses #{settings.color_layer_count} CMY/W color layers #{base_layer_description(settings)}.
        - The backlight-to-view color-layer order is #{settings.pigment_order.map(&:capitalize).join(" -> ")} -> White.
        - White thickness above the color region follows #{thickness_method(settings, calibration_profile)}.
        #{z_part_line(settings)}
        - `preview.png` shows nominal recipe colors with relative thickness shading; it is not a colorimetric prediction.
        - `transmission.png`, `thickness.png`, and the four material masks use the same cells as the 3MF output.
        - `cmyk_white.stl` is a separate monochrome reference model, not the color model.
        - Product: #{profile.product_url}
        - Guide: #{profile.reference_url}
        - Import models without scaling, place the flat back at Z=0, and view the print from +Z.
        #{layer_height_description(settings)}
        - White thickness uses #{settings.pixel_size} mm XY cells; CMYW recipes use
          #{settings.effective_color_pixel_size} mm color cells.
        - Use 100% rectilinear infill and verify every layer in the slicer before printing.
        - The effective thickness range is #{settings.effective_minimum_thickness}–#{settings.effective_maximum_thickness} mm.
      MARKDOWN
    end

    def model_instruction(tile_artifacts, names)
      return "Open `lithop.3mf` for the physical color model; it contains: #{names.join(", ")}." if tile_artifacts.one?

      "Open the #{tile_artifacts.length} 3MF files under `tiles/` and assemble them using " \
        "`tile-layout.svg` and `manifest.json`; together they contain: #{names.join(", ")}."
    end

    def z_part_line(settings)
      return "- Z regions remain combined into the material parts." unless settings.separate_z_parts

      "- Z regions use #{settings.color_region_parts + 1} plates: each CMYW color region includes " \
        "a Base White carrier, followed by Top White; every plate starts at Z=0."
    end

    def profile_material(profile, material)
      profile.materials.find { |candidate| candidate.channel == material }
    end

    def calibration_line(calibration_profile)
      return "- No measured calibration profile was used." unless calibration_profile

      "- Measured calibration profile: #{calibration_profile.profile_id}."
    end

    def thickness_method(_settings, calibration_profile)
      return "the closest measured White luminance stage" if calibration_profile

      "continuous normalized material-display density or Rec. 601 luminance"
    end

    def base_layer_description(settings)
      "above #{settings.base_white_layers} White base layers"
    end

    def layer_height_description(settings)
      upper_height = settings.layer_structure.top_layer_height
      "- Use a #{settings.nozzle_diameter} mm nozzle, #{settings.first_layer_height} mm base layers,\n  " \
        "#{settings.layer_height} mm color layers, and #{upper_height} mm upper White layers."
    end
    private_class_method :model_instruction, :z_part_line, :profile_material, :calibration_line, :thickness_method,
                         :base_layer_description, :layer_height_description
  end
end

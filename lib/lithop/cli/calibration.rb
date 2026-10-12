# frozen_string_literal: true

module Lithop
  # Handles calibration target generation and measured profile loading for the CLI.
  module CLICalibration
    CALIBRATION_SETTING_KEYS = %i[
      minimum_thickness maximum_thickness first_layer_height layer_height nozzle_diameter
      color_model color_layer_count pigment_order maximum_triangles
    ].freeze

    private

    def calibrate(argv)
      options = {}
      parser = CLIOptions.calibration(options, @out)
      arguments = parser.parse(argv)
      raise OptionParser::InvalidArgument, arguments.join(" ") unless arguments.empty?

      project_dir, settings, = load_settings(options, keys: CALIBRATION_SETTING_KEYS)
      result = Calibration::Export.new(settings:, project_dir:).call
      @out.puts "Generated #{result.patch_count} calibration patches and #{result.triangle_count} 3MF triangles"
      @out.puts "in #{result.path}"
      result.files.each { |file| @out.puts "  #{file}" }
      0
    rescue OptionParser::ParseError, Error, SystemCallError => e
      @err.puts "lithop: #{e.message}"
      1
    end

    def load_calibration_profile(path, settings)
      return [nil, nil] unless path

      expanded = File.expand_path(path, @cwd)
      profile = Calibration::Profile.load(expanded)
      profile.validate_for!(settings)
      profile.validate_complete!
      [profile, expanded]
    end
  end
end

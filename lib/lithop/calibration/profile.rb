# frozen_string_literal: true

require "json"

module Lithop
  module Calibration
    # Reads, validates, and writes measured calibration data.
    class Profile
      include ProfileMeasurements

      SCHEMA_VERSION = 1

      attr_reader :data

      def self.template(profile_id:, settings:, target:)
        new(
          "schema_version" => SCHEMA_VERSION,
          "profile_id" => profile_id,
          "status" => "draft",
          "generator_version" => Lithop::VERSION,
          "structure" => structure_for(settings),
          "materials" => Palette::MATERIALS.to_h { |material| [material.to_s, { "lot" => nil }] },
          "lighting" => { "source" => nil, "color_temperature_k" => nil, "illuminance_lux" => nil },
          "measurement" => {
            "method" => nil,
            "device" => nil,
            "white_point" => nil,
            "black_point" => nil,
            "uncertainty" => nil
          },
          "patches" => target.patches.map { |patch| patch_data(patch) }
        )
      end

      def self.load(path)
        new(JSON.parse(File.read(path)))
      rescue JSON::ParserError => e
        raise InputError, "invalid calibration profile JSON: #{e.message}"
      rescue Errno::ENOENT
        raise InputError, "calibration profile does not exist: #{File.expand_path(path)}"
      end

      def self.structure_for(settings)
        {
          "color_model" => settings.color_model,
          "color_layer_count" => settings.color_layer_count,
          "pigment_order" => settings.pigment_order.map(&:to_s),
          "nozzle_diameter_mm" => settings.nozzle_diameter,
          "first_layer_height_mm" => settings.first_layer_height,
          "layer_height_mm" => settings.layer_height
        }
      end

      def self.patch_data(patch)
        {
          "patch_id" => patch.id,
          "kind" => patch.kind.to_s,
          "row" => patch.row,
          "column" => patch.column,
          "recipe" => patch.recipe.to_h.fetch(:counts).transform_keys(&:to_s),
          "total_thickness_mm" => patch.height,
          "top_white_thickness_mm" => patch.top_white_thickness,
          "measurements" => []
        }
      end
      private_class_method :patch_data

      def initialize(data)
        @data = data
        validate!
      end

      def write(path)
        File.write(path, "#{JSON.pretty_generate(data)}\n")
      end

      def validate_for!(settings)
        expected = self.class.send(:structure_for, settings)
        return true if data.fetch("structure") == expected

        raise ConfigurationError, "calibration profile does not match the active layer structure"
      end

      private

      def validate!
        raise InputError, "calibration profile must be a JSON object" unless data.is_a?(Hash)

        unless data["schema_version"] == SCHEMA_VERSION
          version = data["schema_version"]
          raise InputError, "unsupported calibration profile schema_version: #{version.inspect}"
        end
        raise InputError, "calibration profile_id must be a non-empty string" unless present_string?(data["profile_id"])
        raise InputError, "calibration profile structure must be an object" unless data["structure"].is_a?(Hash)
        raise InputError, "calibration profile patches must be an array" unless data["patches"].is_a?(Array)

        data.fetch("patches").each { |patch| validate_patch!(patch) }
      end

      def validate_patch!(patch)
        valid = patch.is_a?(Hash) && present_string?(patch["patch_id"]) &&
                patch["recipe"].is_a?(Hash) && patch["measurements"].is_a?(Array)
        raise InputError, "calibration profile contains an invalid patch" unless valid

        patch.fetch("measurements").each { |measurement| validate_measurement!(measurement) }
      end

      def validate_measurement!(measurement)
        return if measurement.is_a?(Hash) && valid_rgb?(measurement["transmitted_srgb"]) &&
                  nonnegative?(measurement["luminance"]) && optional_nonnegative?(measurement["error"])

        raise InputError,
              "calibration measurements require transmitted_srgb, non-negative luminance, and optional error"
      end

      def valid_rgb?(rgb)
        rgb.is_a?(Array) && rgb.length == 3 &&
          rgb.all? { |value| value.is_a?(Numeric) && value.finite? && value.between?(0.0, 1.0) }
      end

      def nonnegative?(value) = value.is_a?(Numeric) && value.finite? && value >= 0
      def optional_nonnegative?(value) = value.nil? || nonnegative?(value)

      def present_string?(value) = value.is_a?(String) && !value.empty?
    end
  end
end

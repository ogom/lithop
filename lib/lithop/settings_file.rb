# frozen_string_literal: true

require "json"

module Lithop
  # Loads validated generation overrides from a JSON settings file.
  module SettingsFile
    DEFAULT_PATH = File.join("config", "settings.json")
    SCHEMA_VERSION = 1
    ALLOWED_KEYS = (Settings::DEFAULTS.keys.map(&:to_s) + ["schema_version"]).freeze
    Result = Data.define(:path, :values)

    module_function

    def load(path, required: false)
      expanded = File.expand_path(path)
      unless File.exist?(expanded)
        raise ConfigurationError, "settings file does not exist: #{expanded}" if required

        return Result.new(path: nil, values: {})
      end
      raise ConfigurationError, "settings path is not a file: #{expanded}" unless File.file?(expanded)

      data = JSON.parse(File.read(expanded))
      raise ConfigurationError, "settings file must contain a JSON object: #{expanded}" unless data.is_a?(Hash)

      validate_keys!(data, expanded)
      validate_schema!(data, expanded)
      values = normalize_values(data.except("schema_version").transform_keys(&:to_sym))
      Result.new(path: expanded, values:)
    rescue JSON::ParserError => e
      raise ConfigurationError, "settings file is not valid JSON: #{expanded}: #{e.message}"
    rescue SystemCallError => e
      raise ConfigurationError, "could not read settings file: #{expanded}: #{e.message}"
    end

    def normalize_values(values)
      values[:color_model] = values[:color_model].downcase if values[:color_model].is_a?(String)
      values[:image_fit] = values[:image_fit].downcase if values[:image_fit].is_a?(String)
      values[:layout_profile] = values[:layout_profile].downcase if values[:layout_profile].is_a?(String)
      values[:tile_layout] = values[:tile_layout].downcase if values[:tile_layout].is_a?(String)
      values
    end
    private_class_method :normalize_values

    def validate_keys!(data, path)
      unknown = data.keys - ALLOWED_KEYS
      return if unknown.empty?

      raise ConfigurationError, "settings file contains unknown keys: #{unknown.sort.join(", ")}: #{path}"
    end
    private_class_method :validate_keys!

    def validate_schema!(data, path)
      version = data.fetch("schema_version", SCHEMA_VERSION)
      return if version.eql?(SCHEMA_VERSION)

      raise ConfigurationError, "unsupported settings schema_version #{version.inspect}: #{path}"
    end
    private_class_method :validate_schema!
  end
end

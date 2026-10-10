# frozen_string_literal: true

require "optparse"

module Lithop
  # Builds parsers for Lithop's generation and cleanup commands.
  module CLIOptions
    module_function

    def generation(options, out)
      OptionParser.new do |parser|
        parser.banner = "Usage: lithop IMAGE [options]"
        CLIImageOptions.add(parser, options)
        add_print_settings(parser, options)
        add_configuration(parser, options)
        parser.on("--calibration-profile FILE", "Measured calibration profile JSON") do |value|
          options[:calibration_profile] = value
        end
        add_information(parser, out)
      end
    end

    def clean(options, out)
      OptionParser.new do |parser|
        parser.banner = "Usage: lithop clean [--project-dir DIR]"
        parser.on("--project-dir DIR", "Project directory containing build/") do |value|
          options[:project_dir] = value
        end
        parser.on("-h", "--help", "Print help") do
          out.puts parser
          exit 0
        end
      end
    end

    def calibration(options, out)
      OptionParser.new do |parser|
        parser.banner = "Usage: lithop calibrate [options]"
        parser.on("--min-thickness MM", Float, "Requested minimum thickness (default: 1.0)") do |value|
          options[:minimum_thickness] = value
        end
        parser.on("--max-thickness MM", Float, "Requested maximum thickness (default: 2.14689422)") do |value|
          options[:maximum_thickness] = value
        end
        add_print_settings(parser, options)
        add_configuration(parser, options)
        add_information(parser, out)
      end
    end

    def add_print_settings(parser, options)
      parser.on("--first-layer-height MM", Float, "First layer height (default: 0.1)") do |value|
        options[:first_layer_height] = value
      end
      parser.on("--layer-height MM", Float, "Layer height after first layer (default: 0.1)") do |value|
        options[:layer_height] = value
      end
      parser.on("--nozzle-diameter MM", Float, "Nozzle diameter: 0.2/0.4 (default: 0.2)") do |value|
        options[:nozzle_diameter] = value
      end
      parser.on("--color-model MODEL", "Color model (default: cmy)") do |value|
        options[:color_model] = value.downcase
      end
      parser.on("--color-layer-count COUNT", Integer, "CMY/W color layers: 4/5/7 (default: 7)") do |value|
        options[:color_layer_count] = value
      end
      parser.on("--pigment-order LIST", "Pigment order, e.g. cyan,magenta,yellow") do |value|
        options[:pigment_order] = value
      end
    end
    private_class_method :add_print_settings

    def add_configuration(parser, options)
      parser.on("--config FILE", "Input settings JSON (default: PROJECT/config/settings.json)") do |value|
        options[:settings_file] = value
      end
      parser.on("--project-dir DIR", "Project directory containing config/ and build/") do |value|
        options[:project_dir] = value
      end
    end
    private_class_method :add_configuration

    def add_information(parser, out)
      parser.on("-v", "--version", "Print version") do
        out.puts Lithop::VERSION
        exit 0
      end
      parser.on("-h", "--help", "Print help") do
        out.puts parser
        exit 0
      end
    end
    private_class_method :add_information
  end
end

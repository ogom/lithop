# frozen_string_literal: true

module Lithop
  # Adds sRGB, pale-color, and Yellow transmission adjustments.
  module CLIImageAdjustmentOptions
    module_function

    def add(parser, options)
      parser.on("--brightness PERCENT", Float, "Brightness: -100..100 (default: 0)") do |value|
        options[:brightness] = value
      end
      parser.on("--contrast PERCENT", Float, "Contrast: -100..100 (default: 0)") do |value|
        options[:contrast] = value
      end
      parser.on("--saturation PERCENT", Float, "Saturation: -100..100 (default: 0)") do |value|
        options[:saturation] = value
      end
      parser.on("--suppress-pale-colors", "Convert very pale colors to White") do
        options[:suppress_pale_colors] = true
      end
      parser.on("--no-suppress-pale-colors", "Keep very pale colors as CMY candidates (default)") do
        options[:suppress_pale_colors] = false
      end
      parser.on("--yellow-mix-color COLOR", "Pigment mixed into Yellow: cyan/magenta (default: cyan)") do |value|
        options[:yellow_mix_color] = value.downcase
      end
      parser.on(
        "--yellow-mix-percent PERCENT", Float,
        "Yellow coverage replaced by mix pigment: 0..100 (default: 0)"
      ) { |value| options[:yellow_mix_percent] = value }
    end
  end
end

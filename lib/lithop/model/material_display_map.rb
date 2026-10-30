# frozen_string_literal: true

module Lithop
  # Recognizes the material-display mixtures used by the bundled CMY chart.
  module MaterialDisplayMap
    CMY_BLACK = [0.2, 0.4, 0.4].freeze
    CMY_BLACK_DENSITIES = {
      0xF4F4F5 => 0.05, 0xE8E8E9 => 0.1, 0xCFD1D2 => 0.2, 0xB8BABD => 0.3,
      0x9FA3A6 => 0.4, 0x878B8F => 0.5, 0x707479 => 0.6, 0x575D62 => 0.7,
      0x40464D => 0.8, 0x272F36 => 0.9, 0x101820 => 1.0
    }.freeze
    COLOR_CMYS = {
      0x760081 => [0.4, 0.6, 0.0].freeze,
      0x000075 => [0.4, 0.6, 0.0].freeze,
      0x0043A6 => [0.6, 0.4, 0.0].freeze,
      0x0086D6 => [1.0, 0.0, 0.0].freeze,
      0x007F6B => [0.6, 0.0, 0.4].freeze,
      0x007700 => [0.4, 0.0, 0.6].freeze,
      0x7EAD00 => [0.4, 0.0, 0.6].freeze,
      0xFCE300 => [0.0, 0.0, 1.0].freeze,
      0xF37200 => [0.0, 0.4, 0.6].freeze,
      0xE90000 => [0.0, 0.4, 0.6].freeze,
      0xEB0046 => [0.0, 0.6, 0.4].freeze,
      0xEC008C => [0.0, 1.0, 0.0].freeze
    }.freeze
    COLOR_LINES = COLOR_CMYS.map do |packed, cmy|
      rgb = [packed >> 16, (packed >> 8) & 0xFF, packed & 0xFF]
      direction = rgb.map { |component| component - 255 }
      [direction.freeze, direction.sum { |component| component * component }, cmy]
    end.freeze
    MAXIMUM_ERROR = 3.0

    module_function

    def call(rgb, mixtures: true)
      channels = rgb.map { |component| (component * 255).round.clamp(0, 255) }
      packed = channels.reduce(0) { |value, component| (value << 8) | component }
      return [[0.0, 0.0, 0.0], 0.0] if packed == 0xFFFFFF
      return [CMY_BLACK, CMY_BLACK_DENSITIES.fetch(packed)] if CMY_BLACK_DENSITIES.key?(packed)
      return [COLOR_CMYS.fetch(packed), 1.0] if COLOR_CMYS.key?(packed)
      return unless mixtures

      match = closest_line(channels)
      return unless match && match.first <= MAXIMUM_ERROR

      _error, density, cmy = match
      [cmy, density]
    end

    def closest_line(channels)
      offset = channels.map { |component| component - 255 }
      COLOR_LINES.filter_map do |direction, magnitude, cmy|
        density = offset.zip(direction).sum { |value, axis| value * axis }.fdiv(magnitude)
        next unless density.between?(0.0, 1.0)

        error = offset.zip(direction).sum { |value, axis| (value - (density * axis))**2 }
        [error, density, cmy]
      end.min_by(&:first)
    end
    private_class_method :closest_line
  end
end

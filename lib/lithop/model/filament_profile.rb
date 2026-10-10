# frozen_string_literal: true

module Lithop
  # Describes and validates the filament materials used by multipart models.
  module FilamentProfile
    REQUIRED_CHANNELS = %i[cyan magenta yellow white].freeze

    Material = Data.define(:channel, :name, :color_code, :display_color, :diameter_mm) do
      def to_h
        {
          channel:,
          name:,
          color_code:,
          display_color:,
          diameter_mm:
        }
      end
    end

    DisplaySample = Data.define(:cmy, :density)

    Profile = Data.define(:id, :name, :manufacturer, :product_url, :reference_url, :materials) do
      def to_h
        {
          id:,
          name:,
          manufacturer:,
          product_url:,
          reference_url:,
          materials: materials.map(&:to_h)
        }
      end
    end

    BAMBU_LAB_PLA_CMYK = Profile.new(
      id: "bambu_lab_pla_basic_cmyw",
      name: "Bambu Lab PLA Basic CMYW",
      manufacturer: "Bambu Lab",
      product_url: "https://jp.store.bambulab.com/products/pla-cmyk-lithophane",
      reference_url: "https://wiki.bambulab.com/en/knowledge-sharing/CMYK-color-lithophane-printing-instructions",
      materials: [
        Material.new(
          channel: :cyan, name: "PLA Basic Cyan", color_code: "10603",
          display_color: "#0086D6FF", diameter_mm: 1.75
        ),
        Material.new(
          channel: :magenta, name: "PLA Basic Magenta", color_code: "10202",
          display_color: "#EC008CFF", diameter_mm: 1.75
        ),
        Material.new(
          channel: :yellow, name: "PLA Basic Yellow", color_code: "10400",
          display_color: "#FCE300FF", diameter_mm: 1.75
        ),
        Material.new(
          channel: :white, name: "PLA Basic White", color_code: "10100",
          display_color: "#FFFFFFFF", diameter_mm: 1.75
        )
      ].freeze
    ).freeze

    module_function

    def default = BAMBU_LAB_PLA_CMYK

    def display_sample(rgb)
      cmy, density = MaterialDisplayMap.call(rgb)
      DisplaySample.new(cmy:, density:) if cmy
    end

    def display_cmy(rgb) = display_sample(rgb)&.cmy

    def validate!(profile)
      channels = profile.materials.map(&:channel)
      return true if channels == REQUIRED_CHANNELS

      raise ConfigurationError, "filament profile must contain only Cyan, Magenta, Yellow, and White"
    end
  end
end

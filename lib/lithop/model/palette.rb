# frozen_string_literal: true

module Lithop
  # Maps CMY samples to printable CMYW layer recipes.
  class Palette
    PIGMENTS = %i[cyan magenta yellow].freeze
    MATERIALS = [*PIGMENTS, :white].freeze
    SUBTRACTIVE_MIXES = {
      green: %i[cyan yellow].freeze,
      purple: %i[cyan magenta].freeze,
      red: %i[magenta yellow].freeze
    }.freeze
    DEFAULT_LAYER_COUNT = 7

    Recipe = Data.define(:cyan, :magenta, :yellow, :white, :coverage_cmy, :ordered_layers) do
      def layer_count
        cyan + magenta + yellow + white
      end

      def layers = ordered_layers

      def pigments
        PIGMENTS.select { |pigment| public_send(pigment).positive? }
      end

      def to_h
        {
          counts: MATERIALS.to_h { |material| [material, public_send(material)] },
          layers:,
          pigments:,
          coverage_cmy:
        }
      end
    end

    attr_reader :layer_count, :pigment_order, :recipes

    def initialize(layer_count: DEFAULT_LAYER_COUNT, pigment_order: PIGMENTS)
      unless layer_count.is_a?(Integer) && layer_count.positive?
        raise ConfigurationError, "palette layer_count must be a positive integer"
      end

      valid_pigment_order = pigment_order.is_a?(Array) && pigment_order.length == PIGMENTS.length &&
                            pigment_order.sort == PIGMENTS.sort
      unless valid_pigment_order
        raise ConfigurationError, "palette pigment_order must contain cyan, magenta, and yellow exactly once"
      end

      @layer_count = layer_count
      @pigment_order = pigment_order.dup.freeze
      @recipes = build_recipes.freeze
    end

    def nearest(cmy)
      validate_cmy!(cmy)
      recipes.min_by do |recipe|
        recipe.coverage_cmy.zip(cmy).sum { |coverage, target| (coverage - target)**2 }
      end
    end

    def display_color(recipe)
      channels = recipe.coverage_cmy.map { |component| ((1.0 - component) * 255).round.clamp(0, 255) }
      format("#%<red>02X%<green>02X%<blue>02XFF", red: channels[0], green: channels[1], blue: channels[2])
    end

    private

    def build_recipes
      recipes = []
      (0..layer_count).each do |cyan|
        (0..(layer_count - cyan)).each do |magenta|
          (0..(layer_count - cyan - magenta)).each do |yellow|
            white = layer_count - cyan - magenta - yellow
            counts = { cyan:, magenta:, yellow: }
            recipes << Recipe.new(
              cyan:,
              magenta:,
              yellow:,
              white:,
              coverage_cmy: coverage_cmy(cyan:, magenta:, yellow:),
              ordered_layers: pigment_order.flat_map { |pigment| [pigment] * counts.fetch(pigment) } +
                Array.new(white, :white)
            )
          end
        end
      end
      recipes
    end

    def coverage_cmy(cyan:, magenta:, yellow:)
      [cyan, magenta, yellow].map { |layers| layers.fdiv(layer_count) }.freeze
    end

    def validate_cmy!(cmy)
      return if cmy.is_a?(Array) && cmy.length == 3 &&
                cmy.all? { |value| value.is_a?(Numeric) && value.finite? && value.between?(0.0, 1.0) }

      raise InputError, "CMY must contain three values between 0 and 1"
    end
  end
end

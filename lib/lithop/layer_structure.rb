# frozen_string_literal: true

module Lithop
  # Calculates printable Z boundaries and the physical CMYW layer structure.
  # rubocop:disable-next Metrics/ClassLength
  class LayerStructure
    MICRONS_PER_MM = 1_000
    MINIMUM_TOP_WHITE_LAYERS = 3

    attr_reader :first_layer_height, :layer_height, :color_layer_count, :base_white_layers,
                :top_layer_height, :top_white_start, :minimum_top_white_layers,
                :effective_minimum_thickness, :effective_maximum_thickness

    # rubocop:disable-next Metrics/ParameterLists
    def initialize(
      first_layer_height:, layer_height:, color_layer_count:, minimum_thickness:, maximum_thickness:,
      base_white_layers: 1, top_layer_height: nil, top_white_start: nil,
      minimum_top_white_layers: MINIMUM_TOP_WHITE_LAYERS, exact_maximum_thickness: false
    )
      @first_layer_height = first_layer_height
      @layer_height = layer_height
      @color_layer_count = color_layer_count
      @base_white_layers = base_white_layers
      @top_layer_height = top_layer_height || layer_height
      @top_white_start = top_white_start || color_end
      @minimum_top_white_layers = minimum_top_white_layers
      @effective_minimum_thickness = aligned_at_or_above(minimum_thickness)
      @effective_maximum_thickness = if exact_maximum_thickness
                                       maximum_thickness.round(9)
                                     else
                                       aligned_at_or_below(maximum_thickness)
                                     end
    end

    def minimum_physical_thickness
      (top_white_start + (minimum_top_white_layers * top_layer_height)).round(9)
    end

    def quantize_thickness(value)
      printable_thicknesses.min_by { |boundary| [(boundary - value).abs.round(12), -boundary] }
    end

    def normal_layer_count(height)
      boundary_index(height) - base_white_layers
    end

    def top_white_layer_count(height, pigment_layers: color_layer_count)
      boundary_index(height) - base_white_layers - pigment_layers
    end

    def top_white_thickness(height, pigment_layers: color_layer_count)
      return 0.0 if pigment_layers != color_layer_count

      (height - color_end).round(9)
    end

    def z_boundaries(material_layer_count)
      all_boundaries.first(material_layer_count + 1)
    end

    def color_region_thickness = (color_layer_count * layer_height).round(9)
    def base_white_thickness = (base_white_layers * first_layer_height).round(9)
    def minimum_top_white_thickness = (minimum_physical_thickness - color_end).round(9)
    def color_region_start = base_white_thickness
    def color_region_end = color_end

    def color_region_layer_ranges(part_count)
      size, remainder = color_layer_count.divmod(part_count)
      start = base_white_layers
      Array.new(part_count) do |index|
        finish = start + size + (index < remainder ? 1 : 0)
        (start...finish).tap { start = finish }
      end
    end

    def materials_for(recipe_layers, height)
      top_white_layers = top_white_layer_count(height, pigment_layers: recipe_layers.length)
      [*Array.new(base_white_layers, :white), *recipe_layers, *Array.new(top_white_layers, :white)]
    end

    private

    def color_end
      ((base_white_layers * first_layer_height) + color_region_thickness).round(9)
    end

    def aligned_at_or_above(value)
      return top_white_start if value <= top_white_start

      steps = (((value - top_white_start) / top_layer_height) - 1e-9).ceil
      (top_white_start + (steps * top_layer_height)).round(9)
    end

    def aligned_at_or_below(value)
      return 0.0 if value < top_white_start

      steps = (((value - top_white_start) / top_layer_height) + 1e-9).floor
      (top_white_start + (steps * top_layer_height)).round(9)
    end

    def printable_thicknesses
      @printable_thicknesses ||= begin
        values = []
        value = effective_minimum_thickness
        while value <= effective_maximum_thickness + 1e-9
          values << value.round(9)
          value += top_layer_height
        end
        values << effective_maximum_thickness unless values.any? do |candidate|
          same_boundary?(candidate, effective_maximum_thickness)
        end
        values.freeze
      end
    end

    # rubocop:disable-next Metrics/AbcSize
    def all_boundaries
      @all_boundaries ||= begin
        values = [0.0]
        base_white_layers.times { |index| values << ((index + 1) * first_layer_height).round(9) }
        color_layer_count.times do |index|
          values << (color_end - ((color_layer_count - index - 1) * layer_height)).round(9)
        end
        values << top_white_start unless same_boundary?(values.last, top_white_start)
        value = (top_white_start + top_layer_height).round(9)
        while value <= effective_maximum_thickness + 1e-9
          values << value unless values.any? { |candidate| same_boundary?(candidate, value) }
          value = (value + top_layer_height).round(9)
        end
        values << effective_maximum_thickness unless
          values.any? { |candidate| same_boundary?(candidate, effective_maximum_thickness) }
        values.freeze
      end
    end

    def boundary_index(height)
      index = all_boundaries.index { |boundary| same_boundary?(boundary, height) }
      return index if index

      raise ConfigurationError, "thickness #{height} is not a printable layer boundary"
    end

    def same_boundary?(left, right) = (left - right).abs < 1e-8
  end
end

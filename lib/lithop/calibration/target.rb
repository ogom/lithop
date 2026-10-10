# frozen_string_literal: true

module Lithop
  module Calibration
    # Validates the fixed layout requirements of a calibration target.
    module TargetValidation
      private

      def validate_structure!
        unless @settings.color_layer_count == 7 &&
               @settings.pigment_order == Palette::PIGMENTS
          raise ConfigurationError,
                "calibration target requires seven layers in cyan,magenta,yellow pigment order"
        end

        levels = @settings.layer_structure.normal_layer_count(@settings.effective_maximum_thickness) -
                 @settings.layer_structure.normal_layer_count(@settings.effective_minimum_thickness) + 1
        return if levels >= Target::WHITE_STAGE_COUNT

        raise ConfigurationError, "calibration target requires at least eight printable thickness levels"
      end
    end

    # Builds a directly-addressed patch grid without image resampling.
    class Target
      include TargetValidation

      WIDTH = 140.0
      HEIGHT = 104.0
      RECIPE_COLUMNS = 15
      RECIPE_ROWS = 8
      WHITE_STAGE_COUNT = 8
      COLUMNS = RECIPE_COLUMNS + 1
      ROWS = RECIPE_ROWS + 1

      Patch = Data.define(
        :id, :kind, :row, :column, :recipe, :height, :top_white_thickness
      )

      attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries,
                  :cells, :patches, :recipe_patches, :white_patches

      def initialize(settings:)
        @settings = settings
        validate_structure!
        @palette = Palette.new(
          layer_count: settings.color_layer_count,
          pigment_order: settings.pigment_order
        )
        @columns = COLUMNS
        @rows = ROWS
        @x_boundaries = boundaries(columns, WIDTH)
        @y_boundaries = boundaries(rows, HEIGHT)
        @recipe_patches = build_recipe_patches.freeze
        @white_patches = build_white_patches.freeze
        @patches = [*recipe_patches, *white_patches].freeze
        @cells = build_cells.freeze
        maximum_layers = cells.map { |cell| cell.materials.length }.max
        @z_boundaries = @settings.layer_structure.z_boundaries(maximum_layers).freeze
      end

      def material_at(layer, row, column)
        return if layer.negative? || row.negative? || column.negative? || row >= rows || column >= columns

        cells.fetch((row * columns) + column).materials[layer]
      end

      def materials
        @materials ||= cells.flat_map(&:materials).uniq.freeze
      end

      def width = x_boundaries.last
      def height = y_boundaries.last

      private

      def boundaries(count, extent)
        Array.new(count + 1) { |index| (extent * index.fdiv(count)).round(9) }
      end

      def build_recipe_patches
        @palette.recipes.each_with_index.map do |recipe, index|
          row, column = index.divmod(RECIPE_COLUMNS)
          patch(format("R%03d", index), :recipe, row, column, recipe, @settings.effective_minimum_thickness)
        end
      end

      def build_white_patches
        white = @palette.recipes.find { |recipe| recipe.white == @palette.layer_count }
        white_stage_heights.each_with_index.map do |height, column|
          patch(format("W%02d", column), :white_thickness, RECIPE_ROWS, column, white, height)
        end
      end

      def patch(id, kind, row, column, recipe, height)
        Patch.new(
          id:, kind:, row:, column:, recipe:, height:,
          top_white_thickness: @settings.layer_structure.top_white_thickness(
            height, pigment_layers: @palette.layer_count
          )
        )
      end

      def white_stage_heights
        minimum = @settings.effective_minimum_thickness
        maximum = @settings.effective_maximum_thickness
        Array.new(WHITE_STAGE_COUNT) do |index|
          candidate = minimum + ((maximum - minimum) * index.fdiv(WHITE_STAGE_COUNT - 1))
          @settings.quantize_thickness(candidate)
        end
      end

      def build_cells
        indexed = patches.to_h { |patch| [[patch.row, patch.column], patch] }
        marker = recipe_patches.first
        Array.new(rows * columns) do |index|
          row, column = index.divmod(columns)
          cell_for(indexed.fetch([row, column], marker))
        end
      end

      def cell_for(patch)
        top_white_layers = @settings.layer_structure.top_white_layer_count(
          patch.height, pigment_layers: @palette.layer_count
        )
        materials = [
          *Array.new(@settings.base_white_layers, :white),
          *patch.recipe.layers,
          *Array.new(top_white_layers, :white)
        ].freeze
        MaterialModel::Cell.new(height: patch.height, recipe: patch.recipe, materials:)
      end
    end
  end
end

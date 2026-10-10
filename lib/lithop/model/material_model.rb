# frozen_string_literal: true

module Lithop
  # Builds the printable material grid from sampled colors and thicknesses.
  class MaterialModel
    Cell = Data.define(:height, :recipe, :materials)

    attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells

    def initialize(cmys:, heights:, settings:, palette: nil, cell_cmys: nil)
      @columns = settings.columns
      @rows = settings.rows
      @x_boundaries = settings.x_boundaries
      @y_boundaries = settings.y_boundaries
      @palette = palette || Palette.new(
        layer_count: settings.color_layer_count,
        pigment_order: settings.pigment_order
      )
      @settings = settings
      validate_samples!(cmys, heights, cell_cmys)
      @cells = build_cells(cmys, heights, cell_cmys).freeze
      maximum_layers = cells.map { |cell| cell.materials.length }.max
      @z_boundaries = @settings.layer_structure.z_boundaries(maximum_layers).freeze
    end

    def material_at(layer, row, column)
      return if layer.negative? || row.negative? || column.negative?
      return if row >= rows || column >= columns

      cells.fetch((row * columns) + column).materials[layer]
    end

    def materials
      @materials ||= cells.flat_map(&:materials).uniq.freeze
    end

    def recipe_counts
      cells.each_with_object(Hash.new(0)) do |cell, counts|
        key = Palette::MATERIALS.map { |material| cell.recipe.public_send(material) }.join(":")
        counts[key] += 1
      end.freeze
    end

    def recipe_summaries
      counts = cells.each_with_object(Hash.new(0)) { |cell, result| result[cell.recipe] += 1 }
      @palette.recipes.filter_map do |recipe|
        cell_count = counts[recipe]
        next if cell_count.zero?

        { counts: recipe.to_h.fetch(:counts), cells: cell_count }
      end.freeze
    end

    private

    def validate_samples!(cmys, heights, cell_cmys)
      expected = (columns + 1) * (rows + 1)
      raise InputError, "expected #{expected} CMY samples, got #{cmys.length}" unless cmys.length == expected
      raise InputError, "expected #{expected} height samples, got #{heights.length}" unless heights.length == expected
      return if cell_cmys.nil? || cell_cmys.length == columns * rows

      raise InputError, "expected #{columns * rows} color cells, got #{cell_cmys.length}"
    end

    def build_cells(cmys, heights, cell_cmys)
      Array.new(rows * columns) do |index|
        row, column = index.divmod(columns)
        cmy = cell_cmys ? cell_cmys.fetch(index) : average(corners(cmys, row, column))
        height = @settings.quantize_thickness(average(corners(heights, row, column)))
        recipe = @palette.nearest(cmy)
        Cell.new(height:, recipe:, materials: materials_for(recipe, height).freeze)
      end
    end

    def corners(values, row, column)
      stride = columns + 1
      top_left = (row * stride) + column
      [
        values.fetch(top_left),
        values.fetch(top_left + 1),
        values.fetch(top_left + stride),
        values.fetch(top_left + stride + 1)
      ]
    end

    def average(values)
      return values.sum.fdiv(values.length) unless values.first.is_a?(Array)

      values.transpose.map { |components| components.sum.fdiv(components.length) }
    end

    def materials_for(recipe, height)
      top_white_layers = @settings.layer_structure.top_white_layer_count(height, pigment_layers: @palette.layer_count)
      if top_white_layers < @settings.minimum_top_white_layers
        raise ConfigurationError,
              "physical CMYW output requires at least #{minimum_thickness} mm thickness"
      end

      @settings.layer_structure.materials_for(recipe.layers, height)
    end

    def minimum_thickness
      @settings.layer_structure.minimum_physical_thickness
    end
  end
end

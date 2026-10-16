# frozen_string_literal: true

module Lithop
  # Restricts a material model to one contiguous Z-layer range while preserving global Z coordinates.
  class LayerRegionModel
    Cell = Data.define(:materials)

    attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells, :layer_range

    def initialize(model:, layer_range:)
      @columns = model.columns
      @rows = model.rows
      @x_boundaries = model.x_boundaries
      @y_boundaries = model.y_boundaries
      @layer_range = layer_range
      @z_boundaries = model.z_boundaries[layer_range.begin..layer_range.end].freeze
      @cells = model.cells.map do |cell|
        Cell.new(materials: cell.materials.slice(layer_range).to_a.freeze)
      end.freeze
    end

    def materials = @materials ||= cells.flat_map(&:materials).uniq.freeze
  end
end

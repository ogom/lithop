# frozen_string_literal: true

module Lithop
  # Restricts a material model to an arbitrary contiguous Z range.
  class ZRegionModel
    Cell = Data.define(:materials)

    attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells, :z_range

    def initialize(model:, z_range:)
      @columns = model.columns
      @rows = model.rows
      @x_boundaries = model.x_boundaries
      @y_boundaries = model.y_boundaries
      @z_range = z_range
      source_layers = overlapping_layers(model.z_boundaries)
      @z_boundaries = clipped_boundaries(model.z_boundaries, source_layers).freeze
      @cells = model.cells.map do |cell|
        Cell.new(materials: source_layers.map { |layer| cell.materials.fetch(layer) }.freeze)
      end.freeze
    end

    def materials = @materials ||= cells.flat_map(&:materials).uniq.freeze

    private

    def overlapping_layers(boundaries)
      layers = (0...(boundaries.length - 1)).select do |layer|
        boundaries.fetch(layer) < z_range.end && boundaries.fetch(layer + 1) > z_range.begin
      end
      raise InputError, "Z region must overlap the material model" if layers.empty?

      layers.freeze
    end

    def clipped_boundaries(boundaries, layers)
      inner = layers.filter_map do |layer|
        boundary = boundaries.fetch(layer + 1)
        boundary if boundary > z_range.begin && boundary < z_range.end
      end
      [z_range.begin, *inner, z_range.end]
    end
  end
end

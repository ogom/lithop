# frozen_string_literal: true

module Lithop
  # Resolves a deterministic tile grid on existing XY cell boundaries.
  class TileLayout
    Tile = Data.define(
      :id, :row, :column, :row_start, :row_end, :column_start, :column_end,
      :x_min, :x_max, :y_min, :y_max
    ) do
      def width = x_max - x_min
      def height = y_max - y_min
      def offset = { x: x_min, y: y_min }
      def bounds = { x_min:, x_max:, y_min:, y_max: }
    end

    attr_reader :rows, :columns, :tiles

    def initialize(settings)
      @settings = settings
      @rows = settings.resolved_tile_rows
      @columns = settings.resolved_tile_columns
      @tiles = build_tiles.freeze
    end

    private

    def build_tiles
      row_spans = partition(@settings.rows, rows)
      column_spans = partition(@settings.columns, columns)
      row_spans.each_with_index.flat_map do |(row_start, row_end), row|
        column_spans.each_with_index.map do |(column_start, column_end), column|
          Tile.new(
            id: format("tile_r%<row>02d_c%<column>02d", row: row + 1, column: column + 1),
            row: row + 1,
            column: column + 1,
            row_start:, row_end:, column_start:, column_end:,
            x_min: @settings.x_boundaries.fetch(column_start),
            x_max: @settings.x_boundaries.fetch(column_end),
            y_min: (@settings.height - @settings.y_boundaries.fetch(row_end)).round(9),
            y_max: (@settings.height - @settings.y_boundaries.fetch(row_start)).round(9)
          )
        end
      end
    end

    def partition(cell_count, part_count)
      size, remainder = cell_count.divmod(part_count)
      start = 0
      Array.new(part_count) do |index|
        finish = start + size + (index < remainder ? 1 : 0)
        [start, finish].tap { start = finish }
      end
    end
  end

  # Presents one rectangular subset of a material model in tile-local coordinates.
  class TileMaterialModel
    attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :z_boundaries, :cells

    def initialize(model:, tile:)
      @columns = tile.column_end - tile.column_start
      @rows = tile.row_end - tile.row_start
      @x_boundaries = local_boundaries(model.x_boundaries, tile.column_start, tile.column_end)
      @y_boundaries = local_boundaries(model.y_boundaries, tile.row_start, tile.row_end)
      @z_boundaries = model.z_boundaries
      @cells = slice_cells(model, tile).freeze
    end

    def materials = @materials ||= cells.flat_map(&:materials).uniq.freeze

    private

    def local_boundaries(boundaries, first, last)
      origin = boundaries.fetch(first)
      boundaries[first..last].map { |value| (value - origin).round(9) }.freeze
    end

    def slice_cells(model, tile)
      (tile.row_start...tile.row_end).flat_map do |row|
        offset = (row * model.columns) + tile.column_start
        model.cells.slice(offset, columns)
      end
    end
  end

  # Writes a physical-size overview of the tile IDs and assembled placement.
  module TileLayoutSVG
    module_function

    def write(path, settings:, layout:)
      File.write(path, document(settings:, layout:))
    end

    def document(settings:, layout:, background: true)
      rectangles = layout.tiles.map { |tile| tile_element(settings, tile) }.join("\n")
      fill = background ? "#fff" : "none"
      <<~SVG
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="#{settings.width}mm" height="#{settings.height}mm"
             viewBox="0 0 #{settings.width} #{settings.height}">
          <rect width="#{settings.width}" height="#{settings.height}" fill="#{fill}" stroke="#000" stroke-width="0.4"/>
        #{rectangles}
        </svg>
      SVG
    end

    def tile_element(settings, tile)
      y = settings.height - tile.y_max
      font_size = [[tile.width, tile.height].min * 0.12, 5.0].min
      center_x = tile.x_min + (tile.width / 2.0)
      center_y = y + (tile.height / 2.0)
      <<~SVG.chomp
        <g>
          <rect x="#{tile.x_min}" y="#{y}" width="#{tile.width}" height="#{tile.height}"
                fill="none" stroke="#333" stroke-width="0.25"/>
          <text x="#{center_x}" y="#{center_y - (font_size * 0.6)}"
                font-family="sans-serif" font-size="#{font_size}" text-anchor="middle"
                dominant-baseline="middle">#{tile.id}</text>
          <text x="#{center_x}" y="#{center_y + (font_size * 0.6)}"
                font-family="sans-serif" font-size="#{font_size * 0.72}" text-anchor="middle"
                dominant-baseline="middle">#{tile.width.round(3)} × #{tile.height.round(3)} mm</text>
        </g>
      SVG
    end
    private_class_method :tile_element
  end
end

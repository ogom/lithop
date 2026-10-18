# frozen_string_literal: true

module Lithop
  # Writes the nominal color, transmission, thickness, and material-mask previews.
  module ExportPreviews
    module_function

    def write(directory, model:, settings:, white_heights: nil, corrected_input: nil)
      heights = white_heights && cell_heights(white_heights, settings.columns, settings.rows)
      options = {
        model:,
        minimum: settings.effective_minimum_thickness,
        maximum: settings.effective_maximum_thickness,
        heights:
      }
      Preview.write_material(File.join(directory, "preview.png"), **options, transmission_gamma: 0.5)
      Preview.write_transmission(File.join(directory, "transmission.png"), **options)
      Preview.write_thickness(File.join(directory, "thickness.png"), **options)
      Palette::MATERIALS.each do |material|
        Preview.write_mask(File.join(directory, "#{material}-mask.png"), model:, material:)
      end
      File.binwrite(File.join(directory, "corrected-input.png"), corrected_input) if corrected_input
    end

    def write_tiles(directory, tile_artifacts:, settings:, white_heights:)
      return if tile_artifacts.one?

      heights = cell_heights(white_heights, settings.columns, settings.rows)
      tile_artifacts.each do |artifact|
        tile = artifact.tile
        tile_heights = (tile.row_start...tile.row_end).flat_map do |row|
          offset = (row * settings.columns) + tile.column_start
          heights.slice(offset, artifact.material_model.columns)
        end
        Preview.write_material(
          File.join(directory, tile_preview_name(artifact)),
          model: artifact.material_model,
          minimum: settings.effective_minimum_thickness,
          maximum: settings.effective_maximum_thickness,
          heights: tile_heights,
          transmission_gamma: 0.5
        )
      end
    end

    def tile_preview_name(artifact) = artifact.name.sub(/\.3mf\z/, "-preview.png")

    def cell_heights(vertex_heights, columns, rows)
      stride = columns + 1
      Array.new(columns * rows) do |index|
        row, column = index.divmod(columns)
        top_left = (row * stride) + column
        corners = [top_left, top_left + 1, top_left + stride, top_left + stride + 1]
        corners.sum { |corner| vertex_heights.fetch(corner) }.fdiv(4)
      end
    end
    private_class_method :cell_heights
  end
end

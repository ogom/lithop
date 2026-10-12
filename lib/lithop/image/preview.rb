# frozen_string_literal: true

module Lithop
  # Writes cell-based previews from the same material model as the 3MF.
  module Preview
    module_function

    def write_thickness(path, model:, minimum:, maximum:, heights: nil)
      range = maximum - minimum
      pixels = resolved_heights(model, heights).map { |height| thickness_level(height, minimum, range) }
      write(path, model, pixels, bands: 1)
    end

    def write_transmission(path, model:, minimum:, maximum:, heights: nil)
      range = maximum - minimum
      pixels = resolved_heights(model, heights).map { |height| 255 - thickness_level(height, minimum, range) }
      write(path, model, pixels, bands: 1)
    end

    def write_material(path, model:, minimum:, maximum:, heights: nil, transmission_gamma: 1.0)
      range = maximum - minimum
      cell_heights = resolved_heights(model, heights)
      pixels = model.cells.each_with_index.flat_map do |cell, index|
        transmission = (255 - thickness_level(cell_heights.fetch(index), minimum, range)).fdiv(255)
        transmission **= transmission_gamma
        cell.recipe.coverage_cmy.map do |coverage|
          ((1.0 - coverage) * transmission * 255).round.clamp(0, 255)
        end
      end
      write(path, model, pixels, bands: 3)
    end

    def write_mask(path, model:, material:)
      maximum_layers = model.cells.map { |cell| cell.materials.length }.max
      pixels = model.cells.map do |cell|
        (cell.materials.count(material).fdiv(maximum_layers) * 255).round.clamp(0, 255)
      end
      write(path, model, pixels, bands: 1)
    end

    def thickness_level(height, minimum, range)
      return 0 if range.zero?

      (((height - minimum) / range) * 255).round.clamp(0, 255)
    end

    def resolved_heights(model, heights)
      return model.cells.map(&:height) unless heights
      return heights if heights.length == model.cells.length

      raise InputError, "expected #{model.cells.length} preview heights, got #{heights.length}"
    end
    private_class_method :thickness_level, :resolved_heights

    def write(path, model, pixels, bands:)
      require "vips"

      data = pixels.pack("C*")
      Vips::Image.new_from_memory(data, model.columns, model.rows, bands, :uchar).pngsave(path.to_s)
    end
    private_class_method :write
  end
end

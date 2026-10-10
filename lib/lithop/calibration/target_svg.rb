# frozen_string_literal: true

module Lithop
  module Calibration
    # Writes an editable SVG reference with the same patch layout as the calibration 3MF.
    module TargetSVG
      module_function

      def write(path, target)
        File.write(path, document(target))
      end

      def document(target)
        patches = target.patches.to_h { |patch| [[patch.row, patch.column], patch] }
        cells = Array.new(target.rows * target.columns) do |index|
          row, column = index.divmod(target.columns)
          patch = patches[[row, column]]
          cell(target, row, column, patch)
        end
        dimensions = "width=\"#{number(target.width)}mm\" height=\"#{number(target.height)}mm\" " \
                     "viewBox=\"0 0 #{number(target.width)} #{number(target.height)}\""

        <<~SVG
          <?xml version="1.0" encoding="UTF-8"?>
          <svg xmlns="http://www.w3.org/2000/svg" #{dimensions}
               role="img" aria-labelledby="title desc">
            <title id="title">CMYW calibration target</title>
            <desc id="desc">56 CMYW recipes, eight White thickness stages, and a right orientation column.</desc>
            <rect width="#{number(target.width)}" height="#{number(target.height)}" fill="#fff"/>
          #{cells.join}
          </svg>
        SVG
      end

      def cell(target, row, column, patch)
        x0 = target.x_boundaries.fetch(column)
        x1 = target.x_boundaries.fetch(column + 1)
        y0 = target.y_boundaries.fetch(row)
        y1 = target.y_boundaries.fetch(row + 1)
        return orientation_cell(x0, y0, x1 - x0, y1 - y0, row) unless patch

        fill = patch_color(patch)
        text_fill = dark_color?(fill) ? "#fff" : "#111"
        <<~SVG.lines.map { |line| "  #{line}" }.join
          <g class="patch #{patch.kind}" id="#{patch.id}">
            <rect x="#{number(x0)}" y="#{number(y0)}" width="#{number(x1 - x0)}" height="#{number(y1 - y0)}"
                  fill="#{fill}" stroke="#777" stroke-width="0.2"/>
            <text x="#{number((x0 + x1) / 2)}" y="#{number((y0 + y1) / 2)}" fill="#{text_fill}"
                  font-family="monospace" font-size="3" text-anchor="middle" dominant-baseline="middle">#{patch.id}</text>
          </g>
        SVG
      end

      def orientation_cell(x, y, width, height, row)
        label = row.zero? ? "TOP" : ""
        <<~SVG.lines.map { |line| "  #{line}" }.join
          <g class="patch orientation">
            <rect x="#{number(x)}" y="#{number(y)}" width="#{number(width)}" height="#{number(height)}"
                  fill="#fff" stroke="#777" stroke-width="0.2"/>
            <text x="#{number(x + (width / 2))}" y="#{number(y + (height / 2))}" fill="#111"
                  font-family="monospace" font-size="3" text-anchor="middle" dominant-baseline="middle">#{label}</text>
          </g>
        SVG
      end

      def patch_color(patch)
        return recipe_color(patch.recipe) if patch.kind == :recipe

        stage = patch.id.delete_prefix("W").to_i
        value = (255 * (1.0 - stage.fdiv(Target::WHITE_STAGE_COUNT - 1))).round
        format("#%<value>02X%<value>02X%<value>02X", value:)
      end

      def recipe_color(recipe)
        channels = recipe.coverage_cmy.map { |component| ((1.0 - component) * 255).round }
        format("#%<red>02X%<green>02X%<blue>02X", red: channels[0], green: channels[1], blue: channels[2])
      end

      def dark_color?(color)
        red, green, blue = color.scan(/[0-9A-F]{2}/).map { |channel| channel.to_i(16) }
        ((red * 299) + (green * 587) + (blue * 114)) < 128_000
      end

      def number(value)
        format("%.6f", value).sub(/\.?0+\z/, "")
      end
    end
  end
end

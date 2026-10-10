# frozen_string_literal: true

module Lithop
  # Calculates the XY sampling grid, partial edge cells, and sampled margins.
  class SamplingGrid
    attr_reader :columns, :rows, :x_boundaries, :y_boundaries, :margin_samples

    def initialize(width:, height:, pixel_size:, margins:, columns: nil, rows: nil)
      @columns = columns || (width / pixel_size).ceil
      @rows = rows || (height / pixel_size).ceil
      @x_boundaries = boundaries(width, pixel_size, @columns, fitted: !columns.nil?).freeze
      @y_boundaries = boundaries(height, pixel_size, @rows, fitted: !rows.nil?).freeze
      x_size = width.fdiv(@columns)
      y_size = height.fdiv(@rows)
      @margin_samples = {
        top: (margins.fetch(:top) / y_size).round,
        right: (margins.fetch(:right) / x_size).round,
        bottom: (margins.fetch(:bottom) / y_size).round,
        left: (margins.fetch(:left) / x_size).round
      }.freeze
    end

    def sample_width = columns + 1
    def sample_height = rows + 1

    def content_sample_size
      [
        sample_width - margin_samples.fetch(:left) - margin_samples.fetch(:right),
        sample_height - margin_samples.fetch(:top) - margin_samples.fetch(:bottom)
      ]
    end

    private

    def boundaries(length, pixel_size, count, fitted:)
      return Array.new(count + 1) { |index| (length * index.fdiv(count)).round(9) } if fitted

      Array.new(count + 1) { |index| index == count ? length : [index * pixel_size, length].min }
    end
  end
end

# frozen_string_literal: true

module Lithop
  # Fits an image to one sampling grid and adds configured White margins.
  class ImagePlacement
    def initialize(settings)
      @settings = settings
    end

    def call(image, grid)
      target_width = grid.sample_width
      target_height = grid.sample_height
      margins = grid.margin_samples
      content_width, content_height = grid.content_sample_size
      raise InputError, "margins leave no image samples" unless content_width.positive? && content_height.positive?

      place(image, content_width, content_height).embed(
        margins.fetch(:left), margins.fetch(:top), target_width, target_height,
        extend: :background, background: Array.new(image.bands, 255)
      )
    end

    private

    def place(image, target_width, target_height)
      return contain(image, target_width, target_height) if @settings.image_fit == "contain"

      cover(image, target_width, target_height)
    end

    def cover(image, target_width, target_height)
      scale = [target_width.fdiv(image.width), target_height.fdiv(image.height)].max / @settings.crop_scale
      resized = image.resize(scale)
      left = position_offset(resized.width - target_width, @settings.crop_position_x)
      top = position_offset(resized.height - target_height, @settings.crop_position_y)
      resized.crop(left, top, target_width, target_height)
    end

    def contain(image, target_width, target_height)
      scale = [target_width.fdiv(image.width), target_height.fdiv(image.height)].min * @settings.crop_scale
      resized = image.resize(scale)
      left = position_offset(target_width - resized.width, @settings.crop_position_x)
      top = position_offset(target_height - resized.height, @settings.crop_position_y)
      resized.embed(
        left, top, target_width, target_height,
        extend: :background, background: Array.new(image.bands, 255)
      )
    end

    def position_offset(available, position)
      [(available * position).floor, 0].max
    end
  end
end

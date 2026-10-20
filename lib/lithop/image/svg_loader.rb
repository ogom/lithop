# frozen_string_literal: true

require "rexml/document"
require "rexml/xpath"

module Lithop
  # Applies the self-contained, static subset accepted for SVG input.
  class SVGDocumentValidator
    FORBIDDEN_ELEMENTS = %w[script foreignobject animate animatemotion animatetransform set].freeze
    LENGTH = /\A\+?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?(?:px|mm|in)?\z/i
    NUMBER = /[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?/
    URL_REFERENCE = /url\s*\(\s*(?:(['"])(.*?)\1|([^)]*))\s*\)/im

    def call(data)
      validate_declarations!(data)
      document = parse(data)
      validate_document!(document)
    rescue REXML::ParseException => e
      raise InputError, "invalid SVG XML: #{e.message.lines.first.to_s.strip}"
    end

    private

    def parse(data)
      utf8 = data.dup.force_encoding(Encoding::UTF_8)
      raise InputError, "SVG input must use UTF-8 XML" unless utf8.valid_encoding?

      document = REXML::Document.new(utf8)
      root = document.root
      raise InputError, "input must be a JPEG, PNG, or SVG image" unless root&.name&.casecmp?("svg")

      encoding = document.xml_decl&.encoding
      raise InputError, "SVG input must use UTF-8 XML" if encoding && !encoding.casecmp?("UTF-8")

      document
    end

    def validate_declarations!(data)
      return unless data.match?(/<!DOCTYPE\b|<!ENTITY\b|<\?xml-stylesheet\b/i)

      raise InputError, "SVG DTDs, entities, and external stylesheets are not supported"
    end

    def validate_document!(document)
      validate_dimensions!(document.root)
      REXML::XPath.each(document, "//*") { |element| validate_element!(element) }
    end

    def validate_dimensions!(root)
      width = root.attributes["width"]
      height = root.attributes["height"]
      view_box = root.attributes["viewBox"]

      validate_explicit_dimensions!(width, height) if width || height
      raise InputError, "SVG must define positive width and height or a viewBox" unless width || view_box

      validate_view_box!(view_box) if view_box
    end

    def validate_explicit_dimensions!(width, height)
      return if width && height && valid_length?(width) && valid_length?(height)

      raise InputError, "SVG width and height must be positive values in px, mm, or in"
    end

    def validate_view_box!(view_box)
      values = view_box.scan(NUMBER)
      remainder = view_box.gsub(NUMBER, "").gsub(/[\s,]/, "")
      valid = remainder.empty? && values.length == 4 && values.all? { |value| finite_number?(value) }
      valid &&= values[2].to_f.positive? && values[3].to_f.positive?
      raise InputError, "SVG viewBox must contain four finite numbers with positive width and height" unless valid
    end

    def valid_length?(value)
      value = value.strip
      value.match?(LENGTH) && finite_number?(value.sub(/(?:px|mm|in)\z/i, "")) && value.to_f.positive?
    end

    def finite_number?(value)
      Float(value).finite?
    rescue ArgumentError
      false
    end

    def validate_element!(element)
      if FORBIDDEN_ELEMENTS.include?(element.name.downcase)
        raise InputError, "SVG element <#{element.name}> is not supported"
      end

      element.attributes.each_attribute do |attribute|
        name = attribute.expanded_name.downcase
        value = attribute.value.to_s
        validate_href!(value) if name == "href" || name.end_with?(":href")
        raise InputError, "SVG xml:base is not supported" if name == "xml:base"

        validate_css_references!(value)
      end

      return unless element.name.casecmp?("style")

      validate_css_references!(element.texts.map(&:value).join)
    end

    def validate_href!(value)
      value = value.strip
      return if value.match?(/\A#[^\s#]+\z/)

      raise InputError, "SVG external and data references are not supported"
    end

    def validate_css_references!(value)
      css = normalize_css(value)
      raise InputError, "SVG external CSS imports are not supported" if css.match?(/@import\b/i)

      remainder = css.gsub(URL_REFERENCE) do
        reference = Regexp.last_match(2) || Regexp.last_match(3)
        validate_href!(reference.strip)
        ""
      end
      return unless remainder.match?(/url\s*\(/i)

      raise InputError, "SVG contains an invalid CSS URL reference"
    end

    def normalize_css(value)
      css = value.gsub(%r{/\*.*?\*/}m, "").gsub(/\\(?:\r\n|[\n\r\f])/, "")
      css = css.gsub(/\\([0-9a-f]{1,6})[ \t\r\n\f]?/i) { [Regexp.last_match(1).to_i(16)].pack("U") }
      css.gsub(/\\(.)/m, "\\1")
    rescue RangeError
      raise InputError, "SVG contains an invalid CSS escape"
    end
  end

  # Rasterizes a validated SVG at the resolution required by the sampling grids.
  class SVGLoader
    BASE_DPI = 96.0
    MAXIMUM_FILE_BYTES = 15_000_000

    def initialize(settings)
      @settings = settings
      @validator = SVGDocumentValidator.new
    end

    def call(path, access:, sampling_grids: nil)
      data = read(path)
      @validator.call(data)
      ensure_loader!

      probe = render(data, scale: 1.0, access: :sequential)
      validate_rendered_image!(probe, pixels: false)
      scale = render_scale(probe, sampling_grids || default_sampling_grids)
      validate_planned_pixels!(probe, scale)

      image = render(data, scale:, access:)
      validate_rendered_image!(image)
      image
    end

    private

    def read(path)
      raise InputError, "SVG input exceeds #{MAXIMUM_FILE_BYTES} bytes" if File.size(path) > MAXIMUM_FILE_BYTES

      data = File.binread(path, MAXIMUM_FILE_BYTES + 1)
      raise InputError, "SVG input exceeds #{MAXIMUM_FILE_BYTES} bytes" if data.bytesize > MAXIMUM_FILE_BYTES
      raise InputError, "compressed SVG (SVGZ) is not supported" if data.start_with?("\x1F\x8B".b)

      data
    end

    def ensure_loader!
      Vips::Operation.new("svgload_buffer")
    rescue Vips::Error
      raise InputError, "SVG input requires libvips with librsvg support; install libvips with SVG support"
    end

    def render(data, scale:, access:)
      Vips::Image.new_from_buffer(data, "", dpi: BASE_DPI, scale:, unlimited: false, access:)
    rescue Vips::Error => e
      raise InputError, "could not render SVG: #{e.message}"
    end

    def render_scale(image, grids)
      scales = grids.map do |grid|
        width, height = grid.content_sample_size
        ratios = [width.fdiv(image.width), height.fdiv(image.height)]
        @settings.image_fit == "contain" ? ratios.min * @settings.crop_scale : ratios.max / @settings.crop_scale
      end
      [*scales, 1.0 / image.width, 1.0 / image.height].max
    end

    def default_sampling_grids
      grids = [@settings.sampling_grid]
      grids << @settings.color_sampling_grid if @settings.color_pixel_size
      grids
    end

    def validate_planned_pixels!(image, scale)
      width = [(image.width * scale).ceil, 1].max
      height = [(image.height * scale).ceil, 1].max
      validate_pixel_count!(width, height, "SVG rasterization would exceed")
    end

    def validate_rendered_image!(image, pixels: true)
      unless image.get("vips-loader") == "svgload_buffer" && image.width.positive? && image.height.positive?
        raise InputError, "could not render SVG with positive dimensions"
      end

      validate_pixel_count!(image.width, image.height, "SVG rasterization exceeds") if pixels
    end

    def validate_pixel_count!(width, height, prefix)
      return unless width * height > @settings.maximum_input_pixels

      raise InputError, "#{prefix} #{@settings.maximum_input_pixels} pixels"
    end
  end
end

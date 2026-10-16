# frozen_string_literal: true

require "digest"
require "rexml/document"
require "rexml/parsers/pullparser"
require "zip"

module Lithop
  # Streams structural measurements from an existing 3MF without retaining its meshes.
  # rubocop:disable-next Metrics/ClassLength
  class ReferenceThreeMF
    def initialize(path)
      @path = File.expand_path(path)
    end

    def call
      raise InputError, "reference 3MF does not exist: #{@path}" unless File.file?(@path)

      Zip::File.open(@path) do |archive|
        entries = archive.entries
        {
          path: @path,
          sha256: Digest::SHA256.file(@path).hexdigest,
          bytes: File.size(@path),
          entry_count: entries.length,
          entries: entries.map(&:name).sort,
          uncompressed_bytes: entries.sum(&:size),
          models: model_entries(archive),
          parts: parts(archive),
          plates: plates(archive)
        }
      end
    rescue Zip::Error, REXML::ParseException => e
      raise InputError, "could not inspect reference 3MF: #{e.message}"
    end

    private

    def model_entries(archive)
      archive.entries.filter_map do |entry|
        next unless entry.name.start_with?("3D/") && entry.name.end_with?(".model")

        entry.get_input_stream { |stream| inspect_model(entry.name, stream) }
      end
    end

    def inspect_model(name, stream)
      parser = REXML::Parsers::PullParser.new(stream)
      objects = []
      current = nil
      while parser.has_next?
        event = parser.pull
        if event.start_element?
          current = start_object(event) if event[0] == "object"
          inspect_mesh_element(current, event) if current
        elsif event.end_element? && event[0] == "object" && current
          objects << finish_object(current)
          current = nil
        end
      end
      { file: name, objects: }
    end

    def start_object(event)
      {
        id: event[1]["id"], type: event[1]["type"], vertices: 0, triangles: 0, components: 0,
        component_refs: [],
        minimum: [nil, nil, nil], maximum: [nil, nil, nil]
      }
    end

    def inspect_mesh_element(current, event)
      case event[0]
      when "vertex"
        coordinates = %w[x y z].map { |axis| Float(event[1].fetch(axis)) }
        current[:vertices] += 1
        coordinates.each_index do |index|
          current[:minimum][index] = [current[:minimum][index], coordinates[index]].compact.min
          current[:maximum][index] = [current[:maximum][index], coordinates[index]].compact.max
        end
      when "triangle"
        current[:triangles] += 1
      when "component"
        current[:components] += 1
        current[:component_refs] << {
          object_id: event[1]["objectid"],
          transform: transform_values(event[1]["transform"])
        }
      end
    end

    def finish_object(object)
      object.merge(size: object[:maximum].zip(object[:minimum]).map do |maximum, minimum|
        maximum && minimum && (maximum - minimum)
      end)
    end

    def parts(archive)
      document = metadata_document(archive)
      return [] unless document

      document.get_elements("config/object/part").map do |part|
        metadata = part.get_elements("metadata").to_h { |entry| [entry.attributes["key"], entry.attributes["value"]] }
        { id: part.attributes["id"], name: metadata["name"], extruder: integer_or_nil(metadata["extruder"]) }
      end
    end

    def plates(archive)
      document = metadata_document(archive)
      return [] unless document

      document.get_elements("config/plate").map do |plate|
        metadata = plate.get_elements("metadata").to_h { |entry| [entry.attributes["key"], entry.attributes["value"]] }
        object_ids = plate.get_elements("model_instance").filter_map do |instance|
          entry = instance.get_elements("metadata").find { |item| item.attributes["key"] == "object_id" }
          entry && entry.attributes["value"]
        end
        { id: integer_or_nil(metadata["plater_id"]), name: metadata["plater_name"], object_ids: }
      end
    end

    def metadata_document(archive)
      entry = archive.find_entry("Metadata/model_settings.config")
      entry && REXML::Document.new(entry.get_input_stream.read)
    end

    def integer_or_nil(value) = value && Integer(value)

    def transform_values(value)
      return unless value

      value.split.map { |number| Float(number) }
    end
  end
end

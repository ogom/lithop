# frozen_string_literal: true

require "fileutils"
require "zip"
require_relative "three_mf/mesh"
require_relative "three_mf/bambu_metadata"
require_relative "three_mf/part_writer"
require_relative "three_mf/model_writer"

module Lithop
  # Writes multipart 3D Manufacturing Format (3MF) packages.
  # rubocop:disable-next Metrics/ClassLength
  class ThreeMF
    CORE_NAMESPACE = "http://schemas.microsoft.com/3dmanufacturing/core/2015/02"
    MATERIAL_NAMESPACE = "http://schemas.microsoft.com/3dmanufacturing/material/2015/02"
    RELATIONSHIP_NAMESPACE = "http://schemas.openxmlformats.org/package/2006/relationships"
    CONTENT_TYPE_NAMESPACE = "http://schemas.openxmlformats.org/package/2006/content-types"
    MODEL_RELATIONSHIP = "http://schemas.microsoft.com/3dmanufacturing/2013/01/3dmodel"
    MODEL_CONTENT_TYPE = "application/vnd.ms-package.3dmanufacturing-3dmodel+xml"
    ZIP_MUTEX = Mutex.new
    # The Rust indexer consumes triangles once; the Ruby comparison path requires replayable input.
    Part = Data.define(:material, :triangles, :name, :region, :build_z_offset) do
      def initialize(material:, triangles:, name: nil, region: nil, build_z_offset: 0.0)
        super
      end
    end
    Result = Data.define(:vertex_count, :triangle_count, :material_count, :object_count,
                         :triangle_counts_by_material)

    def self.write(path, parts:, profile: FilamentProfile.default, instrumentation: nil, settings: nil)
      new(parts:, profile:, instrumentation:, settings:).write(path)
    end

    def initialize(parts:, profile:, instrumentation: nil, settings: nil)
      FilamentProfile.validate!(profile)
      @profile = profile
      @parts = build_parts(parts)
      @settings = settings
      @instrumentation = if instrumentation.is_a?(Instrumentation)
                           instrumentation
                         else
                           Instrumentation.new(instrumentation)
                         end
    end

    def write(path)
      destination = File.expand_path(path)
      FileUtils.rm_f(destination)
      package = write_package(destination)
      Result.new(
        vertex_count: package.vertex_count,
        triangle_count: package.triangle_count,
        material_count: @parts.map(&:material).uniq.length,
        object_count: @parts.length,
        triangle_counts_by_material: package.triangle_counts_by_material
      )
    rescue Zip::Error => e
      FileUtils.rm_f(destination) if destination
      raise Error, "could not write 3MF: #{e.message}"
    rescue StandardError
      FileUtils.rm_f(destination) if destination
      raise
    end

    private

    def build_parts(parts)
      valid_materials = @profile.materials.map(&:channel)
      validated = parts.map do |part|
        unless valid_materials.include?(part.material)
          raise InputError, "3MF part uses an unknown material: #{part.material.inspect}"
        end
        unless part.build_z_offset.is_a?(Numeric) && part.build_z_offset.finite?
          raise InputError, "3MF part build_z_offset must be a finite number"
        end

        part
      end
      raise InputError, "3MF requires at least one material part" if validated.empty?

      validated.freeze
    end

    def write_package(destination)
      package = nil
      ZIP_MUTEX.synchronize do
        zip64 = Zip.write_zip64_support
        begin
          Zip.write_zip64_support = false
          Zip::OutputStream.open(destination, suppress_extra_fields: true) do |archive|
            @instrumentation.measure(:three_mf_xml_zip) do
              write_entry(archive, "[Content_Types].xml", content_types_xml)
              write_entry(archive, "_rels/.rels", relationships_xml)
            end
            package = ThreeMFModelWriter.new(
              archive, @parts, @profile, instrumentation: @instrumentation, settings: @settings
            ).write
          end
        ensure
          Zip.write_zip64_support = zip64
        end
      end
      package
    end

    def content_types_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Types xmlns="#{CONTENT_TYPE_NAMESPACE}">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="model" ContentType="#{MODEL_CONTENT_TYPE}"/>
          <Default Extension="config" ContentType="application/xml"/>
        </Types>
      XML
    end

    def relationships_xml
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <Relationships xmlns="#{RELATIONSHIP_NAMESPACE}">
          <Relationship Target="/3D/3dmodel.model" Id="rel-1" Type="#{MODEL_RELATIONSHIP}"/>
        </Relationships>
      XML
    end

    def write_entry(archive, name, contents)
      archive.put_next_entry(name)
      archive.write(contents)
    end
  end
end

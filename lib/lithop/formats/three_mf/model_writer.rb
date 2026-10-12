# frozen_string_literal: true

module Lithop
  # Serializes model resources and build items into a 3MF model document.
  class ThreeMFModelWriter
    CUSTOM_NAMESPACE = "https://github.com/ogom/lithop/3mf/v1"
    BASE_MATERIALS_ID = 1
    COLOR_GROUP_ID = 2
    FIRST_OBJECT_ID = 3
    Result = Data.define(:vertex_count, :triangle_count, :triangle_counts_by_material)

    def initialize(archive, parts, profile, instrumentation: Instrumentation.new, settings: nil)
      @archive = archive
      @parts = parts
      @profile = profile
      @instrumentation = instrumentation
      @settings = settings
    end

    def write
      measure_xml do
        @archive.write(model_header)
        write_materials
      end
      object_ids, result = write_parts
      assembly_id = object_ids.max + 1
      measure_xml do
        write_assembly(assembly_id, object_ids)
        @archive.write("  </resources>\n  <build>\n    <item objectid=\"#{assembly_id}\"/>\n  </build>\n</model>\n")
        ThreeMFBambuMetadata.new(
          archive: @archive,
          assembly_id:,
          object_ids:,
          parts: @parts,
          profile: @profile,
          settings: @settings
        ).write
      end
      result
    end

    private

    def write_materials
      @archive.write("    <m:basematerials id=\"#{BASE_MATERIALS_ID}\">\n")
      @profile.materials.each { |material| @archive.write(material_xml(material)) }
      @archive.write("    </m:basematerials>\n    <m:colorgroup id=\"#{COLOR_GROUP_ID}\">\n")
      @profile.materials.each { |material| @archive.write("      <m:color color=\"#{material.display_color}\"/>\n") }
      @archive.write("    </m:colorgroup>\n")
    end

    def write_parts
      vertex_count = 0
      triangle_counts = {}
      object_ids = @parts.each_with_index.map do |part, index|
        object_id = index + FIRST_OBJECT_ID
        mesh = @instrumentation.measure(:three_mf_indexing) do
          ThreeMFMesh.new(triangles: part.triangles)
        end
        measure_xml do
          ThreeMFPartWriter.new(archive: @archive, profile: @profile).write(object_id, part.material, mesh)
        end
        part.triangles.release_cache! if part.triangles.respond_to?(:release_cache!)
        vertex_count += mesh.vertices.length
        triangle_counts[part.material] = mesh.triangle_count
        object_id
      end
      result = Result.new(
        vertex_count:,
        triangle_count: triangle_counts.values.sum,
        triangle_counts_by_material: triangle_counts.freeze
      )
      [object_ids, result]
    end

    def measure_xml(&)
      @instrumentation.measure(:three_mf_xml_zip, &)
    end

    def write_assembly(assembly_id, object_ids)
      @archive.write("    <object id=\"#{assembly_id}\" type=\"model\" name=\"Lithop CMYW lithophane\">\n")
      @archive.write("      <components>\n")
      object_ids.each { |object_id| @archive.write("        <component objectid=\"#{object_id}\"/>\n") }
      @archive.write("      </components>\n    </object>\n")
    end

    def model_header
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" requiredextensions="m"
          xmlns="#{ThreeMF::CORE_NAMESPACE}"
          xmlns:m="#{ThreeMF::MATERIAL_NAMESPACE}"
          xmlns:lithop="#{CUSTOM_NAMESPACE}">
          <metadata name="Title">Lithop CMYW lithophane</metadata>
          <metadata name="Application">Lithop #{Lithop::VERSION}</metadata>
          <metadata name="Description">Physical CMY subtractive layers with variable White luminance thickness.</metadata>
          <metadata name="lithop:FilamentBundle" preserve="1">#{@profile.name}</metadata>
          <metadata name="lithop:FilamentProduct" preserve="1">#{@profile.product_url}</metadata>
          <metadata name="lithop:PrintingGuide" preserve="1">#{@profile.reference_url}</metadata>
          <resources>
      XML
    end

    def material_xml(material)
      name = "#{@profile.manufacturer} #{material.name} (#{material.color_code})"
      <<~XML
        <m:base name="#{name}" displaycolor="#{material.display_color}"
          lithop:channel="#{material.channel}" lithop:manufacturer="#{@profile.manufacturer}"
          lithop:product="#{material.name}" lithop:colorcode="#{material.color_code}"
          lithop:diameter="#{material.diameter_mm}"/>
      XML
    end
  end
end

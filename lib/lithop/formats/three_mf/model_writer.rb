# frozen_string_literal: true

module Lithop
  # Serializes model resources and build items into a 3MF model document.
  # rubocop:disable-next Metrics/ClassLength
  class ThreeMFModelWriter
    CUSTOM_NAMESPACE = "https://github.com/ogom/lithop/3mf/v1"
    BAMBU_STUDIO_NAMESPACE = "http://schemas.bambulab.com/package/2021"
    BAMBU_STUDIO_APPLICATION = "BambuStudio-02.08.03.66"
    PRODUCTION_NAMESPACE = "http://schemas.microsoft.com/3dmanufacturing/production/2015/06"
    MODEL_PATH = "3D/3dmodel.model"
    BASE_MATERIALS_ID = 1
    COLOR_GROUP_ID = 2
    FIRST_OBJECT_ID = 3
    Result = Data.define(:vertex_count, :triangle_count, :triangle_counts_by_material)
    Assembly = Data.define(:id, :name, :region, :object_ids, :component_origins)

    def initialize(archive, parts, profile, instrumentation: Instrumentation.new, settings: nil)
      @archive = archive
      @parts = parts
      @profile = profile
      @instrumentation = instrumentation
      @settings = settings
    end

    def write
      object_ids = part_object_ids
      assemblies = build_assemblies(object_ids)
      return write_bambu_multi_plate(object_ids, assemblies) if bambu_multi_plate_project?

      measure_xml do
        @archive.put_next_entry(MODEL_PATH)
        @archive.write(model_header)
        write_materials
      end
      result = write_parts(object_ids)
      measure_xml do
        assemblies.each { |assembly| write_assembly(assembly) }
        write_build(assemblies)
        write_bambu_metadata(object_ids, assemblies)
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

    def part_object_ids
      return @parts.each_index.map { |index| index + FIRST_OBJECT_ID }.freeze unless bambu_multi_plate_project?

      next_id = 1
      @parts.group_by(&:region).values.flat_map do |parts|
        ids = Array.new(parts.length) do
          value = next_id
          next_id += 1
          value
        end
        next_id += 1
        ids
      end.freeze
    end

    def write_parts(object_ids)
      vertex_count = 0
      triangle_counts = {}
      object_ids.zip(@parts).each do |object_id, part|
        mesh = @instrumentation.measure(:three_mf_indexing) do
          ThreeMFMesh.new(triangles: part.triangles)
        end
        measure_xml do
          ThreeMFPartWriter.new(archive: @archive, profile: @profile).write(object_id, part, mesh)
        end
        part.triangles.release_cache! if part.triangles.respond_to?(:release_cache!)
        vertex_count += mesh.vertex_count
        triangle_counts[part.material] = triangle_counts.fetch(part.material, 0) + mesh.triangle_count
      end
      Result.new(
        vertex_count:,
        triangle_count: triangle_counts.values.sum,
        triangle_counts_by_material: triangle_counts.freeze
      )
    end

    def write_bambu_multi_plate(object_ids, assemblies)
      result = write_external_parts(object_ids, assemblies)
      write_root_model(assemblies)
      write_model_relationships(assemblies)
      write_bambu_metadata(object_ids, assemblies)
      result
    end

    # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
    def write_external_parts(object_ids, assemblies)
      parts_by_object_id = object_ids.zip(@parts).to_h
      vertex_count = 0
      triangle_counts = {}
      assemblies.each_with_index do |assembly, index|
        @archive.put_next_entry("3D/Objects/object_#{index + 1}.model")
        measure_xml do
          @archive.write(submodel_header)
          write_materials
        end
        assembly.object_ids.each do |object_id|
          part = parts_by_object_id.fetch(object_id)
          mesh = @instrumentation.measure(:three_mf_indexing) do
            ThreeMFMesh.new(triangles: part.triangles)
          end
          center = mesh_center(mesh)
          assembly.component_origins[object_id] = component_origin(
            center, assembly.component_origins.fetch(object_id)
          )
          measure_xml do
            ThreeMFPartWriter.new(
              archive: @archive, profile: @profile, production: true, origin: center
            ).write(object_id, part, mesh)
          end
          part.triangles.release_cache! if part.triangles.respond_to?(:release_cache!)
          vertex_count += mesh.vertex_count
          triangle_counts[part.material] = triangle_counts.fetch(part.material, 0) + mesh.triangle_count
        end
        measure_xml do
          @archive.write("  </resources>\n  <build/>\n</model>\n")
        end
      end
      Result.new(
        vertex_count:,
        triangle_count: triangle_counts.values.sum,
        triangle_counts_by_material: triangle_counts.freeze
      )
    end

    def write_root_model(assemblies)
      @archive.put_next_entry(MODEL_PATH)
      measure_xml do
        @archive.write(bambu_multi_plate_model_header)
        assemblies.each_with_index { |assembly, index| write_assembly(assembly, index + 1) }
        write_build(assemblies)
      end
    end

    def write_model_relationships(assemblies)
      @archive.put_next_entry("3D/_rels/3dmodel.model.rels")
      @archive.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
      @archive.write("<Relationships xmlns=\"#{ThreeMF::RELATIONSHIP_NAMESPACE}\">\n")
      assemblies.each_with_index do |_assembly, index|
        @archive.write(
          " <Relationship Target=\"/3D/Objects/object_#{index + 1}.model\" Id=\"rel-#{index + 1}\" " \
          "Type=\"#{ThreeMF::MODEL_RELATIONSHIP}\"/>\n"
        )
      end
      @archive.write("</Relationships>\n")
    end

    def write_bambu_metadata(object_ids, assemblies)
      ThreeMFBambuMetadata.new(
        archive: @archive,
        object_ids:,
        assemblies:,
        parts: @parts,
        profile: @profile,
        settings: @settings
      ).write
    end

    def measure_xml(&)
      @instrumentation.measure(:three_mf_xml_zip, &)
    end

    def build_assemblies(object_ids)
      groups = if separate_z_plates?
                 object_ids.zip(@parts).group_by { |_object_id, part| part.region }
               else
                 { nil => object_ids.zip(@parts) }
               end
      groups.map do |region, entries|
        Assembly.new(
          id: entries.map(&:first).max + 1,
          name: assembly_name(region),
          region:,
          object_ids: entries.map(&:first).freeze,
          component_origins: entries.to_h { |object_id, part| [object_id, [0.0, 0.0, part.build_z_offset]] }
        )
      end.freeze
    end

    def separate_z_plates?
      @settings&.separate_z_parts && @parts.all?(&:region)
    end

    def bambu_multi_plate_project? = @settings&.bambu_project && separate_z_plates?

    def assembly_name(region)
      return "Lithop CMYW lithophane" unless region
      return "Top White" if region == "top_white"

      region.sub("color_region_", "Color region ")
    end

    def write_assembly(assembly, submodel_index = nil)
      uuid = submodel_index ? production_uuid(assembly.id) : ""
      @archive.write("    <object id=\"#{assembly.id}\"#{uuid} type=\"model\" name=\"#{assembly.name}\">\n")
      @archive.write("      <components>\n")
      assembly.object_ids.each_with_index do |object_id, index|
        transform = component_transform(assembly.component_origins.fetch(object_id))
        path = submodel_index ? %( p:path="/3D/Objects/object_#{submodel_index}.model") : ""
        uuid = submodel_index ? production_uuid((assembly.id * 1000) + index + 1) : ""
        @archive.write("        <component#{path} objectid=\"#{object_id}\"#{uuid}#{transform}/>\n")
      end
      @archive.write("      </components>\n    </object>\n")
    end

    def component_transform(origin)
      return "" if origin.all?(&:zero?)

      %( transform="1 0 0 0 1 0 0 0 1 #{origin.map { |value| format_number(value) }.join(" ")}")
    end

    def format_number(number) = format("%.9g", number)

    def write_build(assemblies)
      @archive.write("  </resources>\n  <build>\n")
      assemblies.each do |assembly|
        attributes = if bambu_multi_plate_project?
                       %(#{build_uuid(assembly.id)} transform="#{build_transform(assembly)}" printable="1")
                     else
                       ""
                     end
        @archive.write("    <item objectid=\"#{assembly.id}\"#{attributes}/>\n")
      end
      @archive.write("  </build>\n</model>\n")
    end

    def production_uuid(identifier)
      %( p:UUID="#{format("%08x", identifier)}-61cb-4c03-9d28-80fed5dfa1dc")
    end

    def build_uuid(identifier)
      %( p:UUID="#{format("%08x", identifier)}-b1ec-4553-aec9-835e5b724bb4")
    end

    def build_transform(assembly)
      x, y = [
        [48.0, 30.0],
        [300.160253, 37.8003226],
        [52.2484968, -205.366274],
        [288.0, -210.0]
      ].fetch(plate_index(assembly))
      "1 0 0 0 1 0 0 0 1 #{format_number(x)} #{format_number(y)} 0"
    end

    def mesh_center(mesh)
      mesh.center
    end

    def component_origin(center, base_origin)
      [center[0], center[1], center[2] + base_origin[2]]
    end

    def plate_index(assembly)
      return 3 if assembly.region == "top_white"

      assembly.region.delete_prefix("color_region_").to_i - 1
    end

    def model_header
      return bambu_multi_plate_model_header if bambu_multi_plate_project?

      inline_model_header
    end

    def inline_model_header
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

    def bambu_multi_plate_model_header
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" requiredextensions="p"
          xmlns="#{ThreeMF::CORE_NAMESPACE}"
          xmlns:BambuStudio="#{BAMBU_STUDIO_NAMESPACE}"
          xmlns:p="#{PRODUCTION_NAMESPACE}"
          xmlns:lithop="#{CUSTOM_NAMESPACE}">
          <metadata name="Title">Lithop CMYW lithophane</metadata>
          <metadata name="Application">#{BAMBU_STUDIO_APPLICATION}</metadata>
          <metadata name="BambuStudio:3mfVersion">1</metadata>
          <metadata name="lithop:Application" preserve="1">Lithop #{Lithop::VERSION}</metadata>
          <metadata name="Description">Physical CMY subtractive layers with variable White luminance thickness.</metadata>
          <metadata name="lithop:FilamentBundle" preserve="1">#{@profile.name}</metadata>
          <metadata name="lithop:FilamentProduct" preserve="1">#{@profile.product_url}</metadata>
          <metadata name="lithop:PrintingGuide" preserve="1">#{@profile.reference_url}</metadata>
          <resources>
      XML
    end

    def submodel_header
      <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <model unit="millimeter" xml:lang="en-US" requiredextensions="m p"
          xmlns="#{ThreeMF::CORE_NAMESPACE}"
          xmlns:m="#{ThreeMF::MATERIAL_NAMESPACE}"
          xmlns:BambuStudio="#{BAMBU_STUDIO_NAMESPACE}"
          xmlns:p="#{PRODUCTION_NAMESPACE}"
          xmlns:lithop="#{CUSTOM_NAMESPACE}">
          <metadata name="BambuStudio:3mfVersion">1</metadata>
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

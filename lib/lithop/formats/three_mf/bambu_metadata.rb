# frozen_string_literal: true

require "json"

module Lithop
  # Writes Bambu Studio material-assignment metadata into a 3MF package.
  # rubocop:disable-next Metrics/ClassLength
  class ThreeMFBambuMetadata
    PATH = "Metadata/model_settings.config"

    def initialize(archive:, object_ids:, assemblies:, parts:, profile:, settings: nil)
      @archive = archive
      @object_ids = object_ids
      @assemblies = assemblies
      @parts = parts
      @profile = profile
      @settings = settings
    end

    def write
      @archive.put_next_entry(PATH)
      @archive.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<config>\n")
      @assemblies.each { |assembly| write_object(assembly) }
      if bambu_project?
        write_plates
        write_assemble if separate_z_plates?
      end
      @archive.write("</config>\n")
      write_project_entries if bambu_project?
    end

    private

    def write_object(assembly)
      @archive.write("  <object id=\"#{assembly.id}\">\n")
      @archive.write("    <metadata key=\"name\" value=\"#{assembly.name}\"/>\n")
      if bambu_project?
        @archive.write("    <metadata key=\"extruder\" value=\"#{root_extruder(assembly)}\"/>\n")
        @archive.write("    <metadata key=\"layer_height\" value=\"#{@settings.layer_height}\"/>\n")
        @archive.write("    <metadata key=\"sparse_infill_density\" value=\"100%\"/>\n")
        @archive.write("    <metadata key=\"sparse_infill_pattern\" value=\"zig-zag\"/>\n")
      end
      part_map = @object_ids.zip(@parts).to_h
      assembly.object_ids.each_with_index do |object_id, volume_id|
        part = part_map.fetch(object_id)
        write_part(object_id, part, assembly, volume_id)
      end
      @archive.write("  </object>\n")
    end

    def root_extruder(assembly)
      return 1 if @assemblies.one?

      part_map = @object_ids.zip(@parts).to_h
      material = part_map.fetch(assembly.object_ids.first).material
      @profile.materials.index { |candidate| candidate.channel == material } + 1
    end

    def write_part(object_id, part, assembly, volume_id)
      material = part.material
      profile_material = @profile.materials.find { |candidate| candidate.channel == material }
      extruder = @profile.materials.index(profile_material) + 1
      uuid = separate_z_plates? ? %( uuid="#{part_uuid(object_id)}") : ""
      @archive.write("    <part id=\"#{object_id}\" subtype=\"normal_part\"#{uuid}>\n")
      @archive.write("      <metadata key=\"name\" value=\"#{part.name || profile_material.name}\"/>\n")
      if separate_z_plates?
        origin = assembly.component_origins.fetch(object_id)
        @archive.write("      <metadata key=\"matrix\" value=\"#{matrix(origin)}\"/>\n")
        @archive.write("      <metadata key=\"source_file\" value=\"lithop.3mf\"/>\n")
        @archive.write("      <metadata key=\"source_object_id\" value=\"#{source_object_id(assembly)}\"/>\n")
        @archive.write("      <metadata key=\"source_volume_id\" value=\"#{volume_id}\"/>\n")
        @archive.write("      <metadata key=\"source_offset_x\" value=\"#{number(origin[0])}\"/>\n")
        @archive.write("      <metadata key=\"source_offset_y\" value=\"#{number(origin[1])}\"/>\n")
        source_z = number(origin[2] - part.build_z_offset)
        @archive.write("      <metadata key=\"source_offset_z\" value=\"#{source_z}\"/>\n")
      end
      @archive.write("      <metadata key=\"extruder\" value=\"#{extruder}\"/>\n")
      @archive.write("    </part>\n")
    end

    def bambu_project? = @settings&.bambu_project

    def part_uuid(object_id)
      format("%08x-7f79-4c88-9311-43ae0fc671e7", object_id)
    end

    def write_plates
      @assemblies.each_with_index { |assembly, index| write_plate(assembly, index + 1) }
    end

    def write_plate(assembly, plate_id)
      name = @assemblies.one? ? "lithophane" : assembly.name
      @archive.write(<<~XML.chomp)
        <plate>
          <metadata key="plater_id" value="#{plate_id}"/>
          <metadata key="plater_name" value="#{name}"/>
          <metadata key="locked" value="false"/>
          <model_instance>
            <metadata key="object_id" value="#{assembly.id}"/>
            <metadata key="instance_id" value="0"/>
      XML
      @archive.write("\n    <metadata key=\"identify_id\" value=\"#{identify_id(plate_id)}\"/>") if separate_z_plates?
      @archive.write("\n  </model_instance>\n</plate>\n")
    end

    def write_assemble
      @archive.write("<assemble>\n")
      @assemblies.each do |assembly|
        @archive.write(
          "  <assemble_item object_id=\"#{assembly.id}\" instance_id=\"0\" " \
          "transform=\"1 0 0 0 1 0 0 0 1 0 0 0\" offset=\"0 0 0\"/>\n"
        )
        assembly.object_ids.each_with_index do |object_id, volume_id|
          transform = volume_transform(assembly.component_origins.fetch(object_id))
          @archive.write(
            "  <assemble_item object_id=\"#{assembly.id}\" volume_id=\"#{volume_id}\" " \
            "transform=\"#{transform}\"/>\n"
          )
        end
      end
      @archive.write("</assemble>\n")
    end

    def separate_z_plates? = @settings&.separate_z_parts && @assemblies.length > 1

    def identify_id(plate_id)
      [218, 253, 276, 287].fetch(plate_id - 1, 287 + (plate_id * 32))
    end

    def volume_transform(origin)
      "1 0 0 0 1 0 0 0 1 #{origin.map { |value| number(value) }.join(" ")}"
    end

    def matrix(origin)
      "1 0 0 #{number(origin[0])} 0 1 0 #{number(origin[1])} 0 0 1 #{number(origin[2])} 0 0 0 1"
    end

    def source_object_id(assembly)
      return 3 if assembly.region == "top_white"

      assembly.region.delete_prefix("color_region_").to_i - 1
    end

    def number(value) = format("%.9g", value)

    def write_project_entries
      write_entry("Metadata/layer_config_ranges.xml", layer_ranges_xml)
      write_entry("Metadata/project_settings.config", "#{JSON.pretty_generate(project_settings)}\n")
    end

    def layer_ranges_xml
      object_id = @assemblies.length
      min_z = @settings.top_white_start
      max_z = @settings.maximum_thickness
      if @settings.separate_z_parts
        color_end = @settings.layer_structure.color_region_end
        min_z = (min_z - color_end).round(9)
        max_z = (max_z - color_end).round(9)
      end
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <objects>
          <object id="#{object_id}">
            <range min_z="#{min_z}" max_z="#{max_z}">
              <option opt_key="extruder">4</option>
              <option opt_key="layer_height">#{@settings.top_layer_height}</option>
            </range>
          </object>
        </objects>
      XML
    end

    def project_settings
      {
        "filament_colour" => %w[#0086D6 #EC008C #FCE300 #FFFFFF],
        "filament_type" => Array.new(4, "PLA"),
        "initial_layer_line_width" => "0.25",
        "initial_layer_print_height" => @settings.first_layer_height.to_s,
        "layer_height" => @settings.layer_height.to_s,
        "line_width" => "0.22",
        "max_layer_height" => ["0.14"],
        "min_layer_height" => [@settings.top_layer_height.to_s],
        "nozzle_diameter" => [@settings.nozzle_diameter.to_s]
      }
    end

    def write_entry(path, contents)
      @archive.put_next_entry(path)
      @archive.write(contents)
    end
  end
end

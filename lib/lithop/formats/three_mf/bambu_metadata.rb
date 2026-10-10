# frozen_string_literal: true

require "json"

module Lithop
  # Writes Bambu Studio material-assignment metadata into a 3MF package.
  class ThreeMFBambuMetadata
    PATH = "Metadata/model_settings.config"
    FIRST_MODEL_OBJECT_INDEX = 1

    def initialize(archive:, assembly_id:, object_ids:, parts:, profile:, settings: nil)
      @archive = archive
      @assembly_id = assembly_id
      @object_ids = object_ids
      @parts = parts
      @profile = profile
      @settings = settings
    end

    def write
      @archive.put_next_entry(PATH)
      @archive.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<config>\n")
      @archive.write("  <object id=\"#{@assembly_id}\">\n")
      @archive.write("    <metadata key=\"name\" value=\"Lithop CMYW lithophane\"/>\n")
      if bambu_project?
        @archive.write("    <metadata key=\"extruder\" value=\"1\"/>\n")
        @archive.write("    <metadata key=\"layer_height\" value=\"#{@settings.layer_height}\"/>\n")
        @archive.write("    <metadata key=\"sparse_infill_density\" value=\"100%\"/>\n")
        @archive.write("    <metadata key=\"sparse_infill_pattern\" value=\"zig-zag\"/>\n")
      end
      @object_ids.zip(@parts).each do |object_id, part|
        write_part(object_id, part.material)
      end
      @archive.write("  </object>\n")
      write_plate if bambu_project?
      @archive.write("</config>\n")
      write_project_entries if bambu_project?
    end

    private

    def write_part(object_id, material)
      profile_material = @profile.materials.find { |candidate| candidate.channel == material }
      extruder = @profile.materials.index(profile_material) + 1
      @archive.write("    <part id=\"#{object_id}\" subtype=\"normal_part\">\n")
      @archive.write("      <metadata key=\"name\" value=\"#{profile_material.name}\"/>\n")
      @archive.write("      <metadata key=\"extruder\" value=\"#{extruder}\"/>\n")
      @archive.write("    </part>\n")
    end

    def bambu_project? = @settings&.bambu_project

    def write_plate
      @archive.write(<<~XML)
        <plate>
          <metadata key="plater_id" value="1"/>
          <metadata key="plater_name" value="lithophane"/>
          <metadata key="locked" value="false"/>
          <model_instance>
            <metadata key="object_id" value="#{@assembly_id}"/>
            <metadata key="instance_id" value="0"/>
          </model_instance>
        </plate>
      XML
    end

    def write_project_entries
      write_entry("Metadata/layer_config_ranges.xml", layer_ranges_xml)
      write_entry("Metadata/project_settings.config", "#{JSON.pretty_generate(project_settings)}\n")
    end

    def layer_ranges_xml
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <objects>
          <object id="#{FIRST_MODEL_OBJECT_INDEX}">
            <range min_z="#{@settings.top_white_start}" max_z="#{@settings.maximum_thickness}">
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

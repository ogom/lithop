# frozen_string_literal: true

module Lithop
  # Serializes one indexed material mesh into a 3MF model document.
  class ThreeMFPartWriter
    def initialize(archive:, profile:)
      @archive = archive
      @profile = profile
    end

    def write(object_id, material, mesh)
      material_index = @profile.materials.index { |candidate| candidate.channel == material }
      name = @profile.materials.fetch(material_index).name
      @archive.write(
        "    <object id=\"#{object_id}\" type=\"model\" name=\"#{name}\" " \
        "pid=\"#{ThreeMFModelWriter::COLOR_GROUP_ID}\" pindex=\"#{material_index}\" " \
        "lithop:channel=\"#{material}\">\n"
      )
      @archive.write("      <mesh>\n        <vertices>\n")
      write_vertices(mesh)
      @archive.write("        </vertices>\n        <triangles>\n")
      write_triangles(mesh)
      @archive.write("        </triangles>\n      </mesh>\n    </object>\n")
    end

    private

    def write_vertices(mesh)
      mesh.vertices.each do |x, y, z|
        @archive.write("          <vertex x=\"#{number(x)}\" y=\"#{number(y)}\" z=\"#{number(z)}\"/>\n")
      end
    end

    def write_triangles(mesh)
      count = 0
      mesh.each_indexed_triangle do |vertices|
        @archive.write(
          "          <triangle v1=\"#{vertices[0]}\" v2=\"#{vertices[1]}\" v3=\"#{vertices[2]}\"/>\n"
        )
        count += 1
      end
      return if count == mesh.triangle_count

      raise InputError, "3MF triangle enumerables must be repeatable"
    end

    def number(value) = format("%.9g", value)
  end
end

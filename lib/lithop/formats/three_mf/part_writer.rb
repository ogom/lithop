# frozen_string_literal: true

module Lithop
  # Serializes one indexed material mesh into a 3MF model document.
  class ThreeMFPartWriter
    XML_BATCH_SIZE = 8_192

    def initialize(archive:, profile:, production: false, origin: nil)
      @archive = archive
      @profile = profile
      @production = production
      @origin = origin || [0.0, 0.0, 0.0]
    end

    def write(object_id, part, mesh)
      material = part.material
      material_index = @profile.materials.index { |candidate| candidate.channel == material }
      name = part.name || @profile.materials.fetch(material_index).name
      region = part.region ? " lithop:region=\"#{part.region}\"" : ""
      uuid = @production ? %( p:UUID="00000000-0000-4000-8000-#{format("%012d", object_id)}") : ""
      @archive.write(
        "    <object id=\"#{object_id}\"#{uuid} type=\"model\" name=\"#{name}\" " \
        "pid=\"#{ThreeMFModelWriter::COLOR_GROUP_ID}\" pindex=\"#{material_index}\" " \
        "lithop:channel=\"#{material}\"#{region}>\n"
      )
      @archive.write("      <mesh>\n        <vertices>\n")
      write_vertices(mesh)
      @archive.write("        </vertices>\n        <triangles>\n")
      write_triangles(mesh)
      @archive.write("        </triangles>\n      </mesh>\n    </object>\n")
    end

    private

    def write_vertices(mesh)
      return write_indexed_native_vertices(mesh) if mesh.native_indexed?
      return write_native_vertices(mesh) if Native.enabled?

      mesh.vertices.each do |x, y, z|
        @archive.write(
          "          <vertex x=\"#{number(x - @origin[0])}\" y=\"#{number(y - @origin[1])}\" " \
          "z=\"#{number(z - @origin[2])}\"/>\n"
        )
      end
    end

    def write_triangles(mesh)
      return write_indexed_native_triangles(mesh) if mesh.native_indexed?
      return write_native_triangles(mesh) if Native.enabled?

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

    def write_native_vertices(mesh)
      mesh.vertices.each_slice(XML_BATCH_SIZE) do |vertices|
        @archive.write(Native.vertex_xml(vertices.flatten, @origin))
      end
    end

    def write_indexed_native_vertices(mesh)
      0.step(mesh.vertex_count - 1, XML_BATCH_SIZE) do |offset|
        @archive.write(mesh.native_mesh.vertex_xml(offset, XML_BATCH_SIZE, @origin))
      end
    end

    def write_native_triangles(mesh)
      count = 0
      mesh.each_indexed_triangle.each_slice(XML_BATCH_SIZE) do |triangles|
        @archive.write(Native.triangle_xml(triangles.flatten))
        count += triangles.length
      end
      return if count == mesh.triangle_count

      raise InputError, "3MF triangle enumerables must be repeatable"
    end

    def write_indexed_native_triangles(mesh)
      0.step(mesh.triangle_count - 1, XML_BATCH_SIZE) do |offset|
        @archive.write(mesh.native_mesh.triangle_xml(offset, XML_BATCH_SIZE))
      end
    end

    def number(value) = format("%.9g", value)
  end
end

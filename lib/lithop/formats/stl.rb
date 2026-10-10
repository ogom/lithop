# frozen_string_literal: true

module Lithop
  # Reads and writes binary stereolithography (STL) triangle meshes.
  module STL
    module_function

    def write(path, triangles)
      count = 0
      File.open(path, "wb") do |file|
        file.write("Lithop binary STL".ljust(80, "\0"))
        file.write([0].pack("V"))
        triangles.each do |triangle|
          normal = normal_for(triangle)
          file.write((normal + triangle.flatten + [0]).pack("e12v"))
          count += 1
        end
        file.seek(80)
        file.write([count].pack("V"))
      end
      count
    end

    def each_triangle(path)
      return enum_for(__method__, path) unless block_given?

      File.open(path, "rb") do |file|
        raise InputError, "STL header is truncated" unless file.read(80)&.bytesize == 80

        count_data = file.read(4)
        raise InputError, "STL triangle count is missing" unless count_data&.bytesize == 4

        count_data.unpack1("V").times do
          record = file.read(50)
          raise InputError, "STL triangle data is truncated" unless record&.bytesize == 50

          values = record.unpack("e12v")
          yield values[3, 9].each_slice(3).to_a
        end
        raise InputError, "STL contains trailing data" unless file.eof?
      end
    end

    def normal_for(triangle)
      a, b, c = triangle
      ab = b.zip(a).map { |left, right| left - right }
      ac = c.zip(a).map { |left, right| left - right }
      cross = [
        (ab[1] * ac[2]) - (ab[2] * ac[1]),
        (ab[2] * ac[0]) - (ab[0] * ac[2]),
        (ab[0] * ac[1]) - (ab[1] * ac[0])
      ]
      magnitude = Math.sqrt(cross.sum { |component| component**2 })
      raise InputError, "cannot write a zero-area triangle" if magnitude.zero?

      cross.map { |component| component / magnitude }
    end
    private_class_method :normal_for
  end
end

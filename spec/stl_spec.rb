# frozen_string_literal: true

RSpec.describe Lithop::STL do
  it "preserves a closed mesh through a binary round trip" do
    geometry = Lithop::Geometry.new(
      heights: [1.0, 1.0, 1.0, 1.0],
      columns: 1,
      rows: 1,
      x_boundaries: [0.0, 2.0],
      y_boundaries: [0.0, 3.0]
    )

    Dir.mktmpdir do |directory|
      path = File.join(directory, "model.stl")
      count = described_class.write(path, geometry.each_triangle)

      expect(count).to eq(12)
      expect(File.size(path)).to eq(84 + (50 * count))
      expect(Lithop::MeshValidator.validate!(described_class.each_triangle(path))).to be(true)
      report = Lithop::MeshValidator.report!(described_class.each_triangle(path))
      expect(report.component_volumes).to eq([6.0])
      expect(report.volume).to eq(6.0)
    end
  end
end

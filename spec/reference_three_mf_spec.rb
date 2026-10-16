# frozen_string_literal: true

RSpec.describe Lithop::ReferenceThreeMF do
  let(:geometry) do
    Lithop::Geometry.new(
      heights: [1.0, 1.0, 1.0, 1.0], columns: 1, rows: 1,
      x_boundaries: [0.0, 1.0], y_boundaries: [0.0, 1.0]
    )
  end

  it "streams model counts, bounds, parts, and plates from a synthetic 3MF" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )
    parts = [Lithop::ThreeMF::Part.new(material: :white, triangles: geometry.each_triangle)]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "reference.3mf")
      Lithop::ThreeMF.write(path, parts:, settings:)
      report = described_class.new(path).call

      expect(report.fetch(:entry_count)).to eq(6)
      expect(report.fetch(:entries)).to include("3D/3dmodel.model", "Metadata/layer_config_ranges.xml")
      expect(report.fetch(:entries).join(" ")).not_to match(/gcode/i)
      expect(report.fetch(:sha256)).to match(/\A[0-9a-f]{64}\z/)
      mesh = report.fetch(:models).find { |model| model.fetch(:file) == "3D/3dmodel.model" }
      object = mesh.fetch(:objects).find { |candidate| candidate.fetch(:triangles).positive? }
      assembly = mesh.fetch(:objects).find { |candidate| candidate.fetch(:components).positive? }
      expect(object.slice(:vertices, :triangles, :size)).to eq(
        vertices: 8, triangles: 12, size: [1.0, 1.0, 1.0]
      )
      expect(assembly.slice(:type, :components)).to eq(type: "model", components: 1)
      expect(report.fetch(:parts)).to eq([{ id: "3", name: "PLA Basic White", extruder: 4 }])
      expect(report.fetch(:plates)).to eq([{ id: 1, name: "lithophane", object_ids: ["4"] }])
    end
  end
end

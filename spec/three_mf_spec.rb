# frozen_string_literal: true

require "zip"

RSpec.describe Lithop::ThreeMF do
  let(:geometry) do
    Lithop::Geometry.new(
      heights: [1.0, 1.0, 1.0, 1.0],
      columns: 1,
      rows: 1,
      x_boundaries: [0.0, 1.0],
      y_boundaries: [0.0, 1.0]
    )
  end

  it "writes a multipart 3MF with physical CMYW material assignments" do
    parts = Lithop::Palette::MATERIALS.map do |material|
      described_class::Part.new(material:, triangles: geometry.each_triangle)
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "color.3mf")
      result = described_class.write(path, parts:)

      expect(result.vertex_count).to eq(32)
      expect(result.triangle_count).to eq(48)
      expect(result.material_count).to eq(4)
      expect(result.object_count).to eq(4)
      expect(result.triangle_counts_by_material).to eq(
        cyan: 12,
        magenta: 12,
        yellow: 12,
        white: 12
      )

      Zip::File.open(path) do |archive|
        expect(archive.map(&:name)).to contain_exactly(
          "[Content_Types].xml",
          "_rels/.rels",
          "3D/3dmodel.model",
          "Metadata/model_settings.config"
        )
        model = archive.read("3D/3dmodel.model")
        expect(model).to include("requiredextensions=\"m\"")
        expect(model).to include('xmlns:lithop="https://github.com/ogom/lithop/3mf/v1"')
        expect(model).to include("<m:basematerials id=\"1\">")
        expect(model).to include("<m:colorgroup id=\"2\">")
        expect(model).to include("<m:color color=\"#0086D6FF\"/>")
        expect(model).to include("Bambu Lab PLA Basic Cyan (10603)")
        expect(model).to include("lithop:colorcode=\"10603\"")
        expect(model).to include("lithop:FilamentBundle")
        expect(model).to include("lithop:PrintingGuide")
        expect(model).to include("name=\"PLA Basic Cyan\" pid=\"2\" pindex=\"0\"")
        expect(model).to include("name=\"PLA Basic White\" pid=\"2\" pindex=\"3\"")
        expect(model.scan("<component objectid=").length).to eq(4)
        expect(model.scan("<triangle ").length).to eq(48)
        settings = archive.read("Metadata/model_settings.config")
        expect(settings).to include("<object id=\"7\">")
        expect(settings).to include("<part id=\"3\" subtype=\"normal_part\">")
        expect(settings).to include("<metadata key=\"extruder\" value=\"1\"/>")
        expect(settings).to include("<metadata key=\"extruder\" value=\"4\"/>")
      end
    end
  end

  it "rejects a part with an unknown material" do
    parts = [described_class::Part.new(material: :black, triangles: geometry.each_triangle)]

    expect { described_class.write("unused.3mf", parts:) }
      .to raise_error(Lithop::InputError, /unknown material/)
  end

  it "rejects a non-finite plate Z offset" do
    parts = [
      described_class::Part.new(material: :white, triangles: geometry.each_triangle, build_z_offset: Float::INFINITY)
    ]

    expect { described_class.write("unused.3mf", parts:) }
      .to raise_error(Lithop::InputError, /build_z_offset must be a finite number/)
  end

  it "rejects a triangle enumerable that cannot be replayed for writing" do
    triangles = Object.new
    source = geometry
    used = false
    triangles.define_singleton_method(:each) do |&block|
      return if used

      used = true
      source.each_triangle.each(&block)
    end
    parts = [described_class::Part.new(material: :white, triangles:)]

    Dir.mktmpdir do |directory|
      path = File.join(directory, "one-shot.3mf")

      expect { described_class.write(path, parts:) }
        .to raise_error(Lithop::InputError, /must be repeatable/)
      expect(File).not_to exist(path)
    end
  end

  it "preserves the fixed extruder number when unused materials are omitted" do
    parts = %i[magenta white].map do |material|
      described_class::Part.new(material:, triangles: geometry.each_triangle)
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "partial-color.3mf")
      described_class.write(path, parts:)

      Zip::File.open(path) do |archive|
        settings = archive.read("Metadata/model_settings.config")
        expect(settings).to include("PLA Basic Magenta")
        expect(settings).to include('<metadata key="extruder" value="2"/>')
        expect(settings).to include("PLA Basic White")
        expect(settings).to include('<metadata key="extruder" value="4"/>')
        expect(settings).not_to include('<metadata key="extruder" value="1"/>')
      end
    end
  end

  it "allows named Z-region parts to share one material and extruder" do
    parts = ["Base White", "Top White"].map do |name|
      described_class::Part.new(material: :white, triangles: geometry.each_triangle, name:, region: "white")
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "white-regions.3mf")
      result = described_class.write(path, parts:)

      expect(result.material_count).to eq(1)
      expect(result.object_count).to eq(2)
      expect(result.triangle_counts_by_material).to eq(white: 24)
      Zip::File.open(path) do |archive|
        model = archive.read("3D/3dmodel.model")
        metadata = archive.read("Metadata/model_settings.config")
        expect(model).to include('name="Base White"', 'name="Top White"', 'lithop:region="white"')
        expect(metadata).to include('value="Base White"', 'value="Top White"')
        expect(metadata.scan('<metadata key="extruder" value="4"/>').length).to eq(2)
      end
    end
  end

  it "writes the reference single-plate Bambu metadata without a Black material" do
    settings = Lithop::Settings.new(
      layout_profile: "standard",
      width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1
    )
    parts = Lithop::Palette::MATERIALS.map do |material|
      described_class::Part.new(material:, triangles: geometry.each_triangle)
    end

    Dir.mktmpdir do |directory|
      path = File.join(directory, "reference.3mf")
      described_class.write(path, parts:, settings:)

      Zip::File.open(path) do |archive|
        expect(archive.map(&:name)).to include(
          "Metadata/model_settings.config",
          "Metadata/layer_config_ranges.xml",
          "Metadata/project_settings.config"
        )
        model_settings = archive.read("Metadata/model_settings.config")
        expect(model_settings).to include('<metadata key="plater_name" value="lithophane"/>')
        expect(model_settings).to include('<metadata key="extruder" value="1"/>')
        expect(model_settings).to include('<metadata key="extruder" value="4"/>')
        layer_ranges = archive.read("Metadata/layer_config_ranges.xml")
        expect(layer_ranges).to include('<object id="1">')
        expect(layer_ranges).to include('min_z="1.0" max_z="2.14689422"')
        expect(layer_ranges).to include('<option opt_key="extruder">4</option>')
        expect(layer_ranges).to include('<option opt_key="layer_height">0.04</option>')
        project = JSON.parse(archive.read("Metadata/project_settings.config"))
        expect(project.fetch("filament_colour")).to eq(%w[#0086D6 #EC008C #FCE300 #FFFFFF])
        expect(project.fetch("min_layer_height")).to eq(["0.04"])
        expect(project.fetch("max_layer_height")).to eq(["0.14"])
      end
    end
  end

  it "rejects a filament profile containing anything other than CMYW" do
    profile = Lithop::FilamentProfile::Profile.new(
      id: "invalid",
      name: "Invalid",
      manufacturer: "Example",
      product_url: "https://example.com",
      reference_url: "https://example.com/guide",
      materials: Lithop::FilamentProfile.default.materials.first(3)
    )
    parts = [described_class::Part.new(material: :white, triangles: geometry.each_triangle)]

    expect do
      described_class.write("unused.3mf", parts:, profile:)
    end.to raise_error(Lithop::ConfigurationError, /only Cyan, Magenta, Yellow, and White/)
  end
end

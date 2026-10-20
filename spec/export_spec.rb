# frozen_string_literal: true

require "vips"
require "json"
require "digest"

RSpec.describe Lithop::Export do
  let(:clock) { instance_double("Clock", now: Time.utc(2026, 10, 6)) }
  let(:random) { instance_double("Random", hex: "12345678") }

  it "exports a complete job atomically" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      pixels = [255, 0, 0, 255].pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 1, :uchar).pngsave(input)
      settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0, nozzle_diameter: 0.4)
      exporter = described_class.new(
        settings:,
        project_dir: directory,
        clock:,
        random:
      )

      result = exporter.call(input)

      expect(result.job_id).to eq("20261006T000000Z-12345678")
      expect(File).to exist(File.join(result.path, "cmyk_white.stl"))
      expect(File).to exist(File.join(result.path, "lithop.3mf"))
      expect(File).to exist(File.join(result.path, "manifest.json"))
      preview_files = %w[
        corrected-input.png preview.png transmission.png thickness.png
        cyan-mask.png magenta-mask.png yellow-mask.png white-mask.png
      ]
      expect(preview_files).to all(satisfy { |name| File.exist?(File.join(result.path, name)) })
      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      expect(manifest.dig("filament_profile", "id")).to eq("bambu_lab_pla_basic_cmyw")
      expect(manifest.fetch("parts").last.fetch("materials")).to eq(%w[Cyan Magenta Yellow White])
      expect(manifest.dig("print_settings", "nozzle_diameter_mm")).to eq(0.4)
      expect(manifest.dig("color_model", "id")).to eq("cmy")
      expect(manifest.dig("color_model", "color_layer_count")).to eq(7)
      expect(manifest.dig("color_model", "pigment_order")).to eq(%w[cyan magenta yellow])
      expect(manifest.dig("color_model", "used_materials")).to eq(%w[Cyan Magenta Yellow White])
      expect(manifest.dig("color_model", "unused_materials")).to be_empty
      expect(manifest.dig("color_model", "bambu_studio_material_assignments_encoded")).to be(true)
      expect(manifest.dig("color_model", "subtractive_mixes", "green")).to eq(%w[cyan yellow])
      expect(manifest.dig("color_model", "subtractive_mixes", "purple")).to eq(%w[cyan magenta])
      expect(manifest.dig("color_model", "luminance_control")).to eq(
        "material" => "White",
        "method" => "normalized_material_display_density_or_rec601_luminance_continuous"
      )
      expect(manifest.dig("color_model", "preview")).to eq(
        "method" => "nominal_recipe_color_with_relative_thickness",
        "colorimetric" => false,
        "source" => "same_material_model_as_3mf",
        "calibration_profile_id" => nil
      )
      expect(manifest.fetch("files")).to include(
        "corrected-input.png", "preview.png", "transmission.png", "thickness.png", "cyan-mask.png",
        "magenta-mask.png", "yellow-mask.png", "white-mask.png"
      )
      settings_json = JSON.parse(File.read(File.join(result.path, "settings.json")))
      expect(settings_json.fetch("nozzle_diameter")).to eq(0.4)
      expect(settings_json.fetch("color_pixel_size")).to be_nil
      expect(settings_json.fetch("effective_color_pixel_size")).to eq(1.0)
      expect(settings_json.slice("margin_top", "margin_right", "margin_bottom", "margin_left")).to eq(
        "margin_top" => 0.0,
        "margin_right" => 0.0,
        "margin_bottom" => 0.0,
        "margin_left" => 0.0
      )
      print_readme = File.read(File.join(result.path, "PRINT_README.md"))
      expect(print_readme).to include("# Lithop print guide")
      expect(print_readme).to include("PLA Basic Cyan, PLA Basic Magenta, PLA Basic Yellow, PLA Basic White")
      expect(print_readme).to include("4 White")
      expect(print_readme).to include("7 CMY/W color layers")
      expect(print_readme).to include("Use a 0.4 mm nozzle")
      expect(print_readme).to include("White thickness uses 1.0 mm XY cells")
      expect(print_readme).to include("CMYW recipes use\n  1.0 mm color cells")
      expect(Dir).not_to exist(File.join(directory, "build", ".tmp-#{result.job_id}"))
      triangles = Lithop::STL.each_triangle(File.join(result.path, "cmyk_white.stl"))
      expect(Lithop::MeshValidator.validate!(triangles)).to be(true)
    end
  end

  it "exports SVG input while preserving and hashing the original source" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.svg")
      source = <<~SVG
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 2">
          <rect width="2" height="2" fill="#0086D6"/>
        </svg>
      SVG
      File.write(input, source)
      exporter = described_class.new(
        settings: Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0),
        project_dir: directory,
        clock:,
        random:
      )

      result = exporter.call(input)
      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      resolved = JSON.parse(File.read(File.join(result.path, "settings.json")))

      expect(File.read(input)).to eq(source)
      expect(manifest.fetch("input_sha256")).to eq(Digest::SHA256.hexdigest(source))
      expect(manifest.dig("color_model", "used_materials")).to eq(%w[Cyan White])
      expect(manifest.dig("color_model", "recipe_summaries")).to eq(
        [{ "counts" => { "cyan" => 7, "magenta" => 0, "yellow" => 0, "white" => 0 }, "cells" => 4 }]
      )
      expect(resolved.fetch("input_path")).to eq(input)
      expect(result.files).to include("lithop.3mf", "cmyk_white.stl", "preview.png")
    end
  end

  it "writes the requested number of local-origin 3MF tiles and their assembled coordinates" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      pixels = ([64, 96, 128] * 24).pack("C*")
      Vips::Image.new_from_memory(pixels, 6, 4, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(
        width: 6.0, height: 4.0, grid_columns: 6, grid_rows: 4,
        tile_count: 6, tile_layout: "grid", tile_rows: 2, tile_columns: 3,
        separate_z_parts: true, color_region_parts: 3
      )

      result = described_class.new(settings:, project_dir: directory, clock:, random:).call(input)
      tile_files = result.files.grep(%r{\Atiles/.+\.3mf\z})
      tile_previews = result.files.grep(%r{\Atiles/.+-preview\.png\z})
      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))

      expect(tile_files).to eq(%w[
                                 tiles/tile_r01_c01.3mf tiles/tile_r01_c02.3mf tiles/tile_r01_c03.3mf
                                 tiles/tile_r02_c01.3mf tiles/tile_r02_c02.3mf tiles/tile_r02_c03.3mf
                               ])
      expect(tile_previews).to eq(%w[
                                    tiles/tile_r01_c01-preview.png tiles/tile_r01_c02-preview.png
                                    tiles/tile_r01_c03-preview.png tiles/tile_r02_c01-preview.png
                                    tiles/tile_r02_c02-preview.png tiles/tile_r02_c03-preview.png
                                  ])
      expect(result.files).to include("tile-layout.svg")
      expect(result.files).not_to include("lithop.3mf")
      expect(File.read(File.join(result.path, "tile-layout.svg"))).to include("2.0 × 2.0 mm")
      expect(manifest.fetch("files")).to match_array(result.files)
      expect(manifest.fetch("tile_layout")).to include(
        "requested" => "grid", "tile_count" => 6, "rows" => 2, "columns" => 3
      )
      expect(manifest.fetch("tiles").first).to include(
        "id" => "tile_r01_c01",
        "preview_file" => "tiles/tile_r01_c01-preview.png",
        "offset_mm" => { "x" => 0.0, "y" => 2.0 },
        "bounds_mm" => { "x_min" => 0.0, "x_max" => 2.0, "y_min" => 2.0, "y_max" => 4.0 }
      )
      expect(manifest.fetch("tiles").last).to include(
        "id" => "tile_r02_c03",
        "preview_file" => "tiles/tile_r02_c03-preview.png",
        "offset_mm" => { "x" => 4.0, "y" => 0.0 },
        "bounds_mm" => { "x_min" => 4.0, "x_max" => 6.0, "y_min" => 0.0, "y_max" => 2.0 }
      )
      tile_previews.each do |name|
        image = Vips::Image.new_from_file(File.join(result.path, name))
        expect([image.width, image.height]).to eq([2, 2])
      end
      tile_files.each do |name|
        report = Lithop::ReferenceThreeMF.new(File.join(result.path, name)).call
        part_names = report.fetch(:parts).map { |part| part.fetch(:name) }
        expect(part_names).to include("Top White")
        expect(part_names.grep(/ Base White\z/).length).to eq(3)
        expect(part_names.grep(/\AColor region [123] /).map { |part_name| part_name.split.fetch(2) }.uniq)
          .to eq(%w[1 2 3])
        mesh_objects = report.fetch(:models).flat_map { |model| model.fetch(:objects) }
                             .select { |object| object.fetch(:triangles).positive? }
        mesh_objects.each do |object|
          expect(object.fetch(:minimum).first(2)).to eq([-1.0, -1.0])
          expect(object.fetch(:maximum).first(2)).to eq([1.0, 1.0])
        end
      end
    end
  end

  it "adds Base White to each CMYW Z region and writes four Bambu Studio plates" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "cyan.svg")
      File.write(
        input,
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1">' \
        '<rect width="1" height="1" fill="#0086D6"/></svg>'
      )
      settings = Lithop::Settings.new(
        width: 1.0, height: 1.0, grid_columns: 1, grid_rows: 1,
        separate_z_parts: true, color_region_parts: 3
      )

      result = described_class.new(settings:, project_dir: directory, clock:, random:).call(input)
      report = Lithop::ReferenceThreeMF.new(File.join(result.path, "lithop.3mf")).call
      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      parts = report.fetch(:parts)
      objects = report.fetch(:models).flat_map { |model| model.fetch(:objects) }.to_h do |object|
        [object.fetch(:id), object]
      end

      expect(parts.map { |part| part.fetch(:name) }).to eq(
        [
          "Color region 1 Base White", "Color region 1 White", "Color region 1 Cyan",
          "Color region 2 Base White", "Color region 2 White", "Color region 2 Cyan",
          "Color region 3 Base White", "Color region 3 White", "Color region 3 Cyan",
          "Top White"
        ]
      )
      expect(parts.map { |part| part.fetch(:extruder) }).to eq([4, 4, 1, 4, 4, 1, 4, 4, 1, 4])
      expect(result.object_count).to eq(10)
      expect(report.fetch(:plates)).to eq(
        [
          { id: 1, name: "Color region 1", object_ids: ["4"] },
          { id: 2, name: "Color region 2", object_ids: ["8"] },
          { id: 3, name: "Color region 3", object_ids: ["12"] },
          { id: 4, name: "Top White", object_ids: ["14"] }
        ]
      )
      assemblies = objects.values.select { |object| object.fetch(:components).positive? }
      expect(assemblies.map { |object| object.fetch(:component_refs).first.fetch(:transform)&.last })
        .to eq([0.1, 0.1, 0.1, 0.05])
      expect(objects.fetch(parts.fetch(0).fetch(:id)).values_at(:minimum, :maximum).map(&:last)).to eq([-0.1, 0.1])
      expect(objects.fetch(parts.fetch(1).fetch(:id)).values_at(:minimum, :maximum).map(&:last)).to eq([-0.15, 0.15])
      expect(objects.fetch(parts.fetch(4).fetch(:id)).values_at(:minimum, :maximum).map(&:last)).to eq([-0.1, 0.1])
      expect(objects.fetch(parts.fetch(7).fetch(:id)).values_at(:minimum, :maximum).map(&:last)).to eq([-0.1, 0.1])
      expect(objects.fetch(parts.fetch(9).fetch(:id)).fetch(:minimum).last).to eq(-0.05)
      expect(manifest.dig("color_model", "z_part_separation", "enabled")).to be(true)
      expect(manifest.dig("color_model", "z_part_separation", "color_regions")).to eq(
        [
          { "id" => "color_region_1", "layer_start" => 1, "layer_end" => 3, "z_min" => 0.2, "z_max" => 0.5 },
          { "id" => "color_region_2", "layer_start" => 4, "layer_end" => 5, "z_min" => 0.5, "z_max" => 0.7 },
          { "id" => "color_region_3", "layer_start" => 6, "layer_end" => 7, "z_min" => 0.7, "z_max" => 0.9 }
        ]
      )
      expect(manifest.dig("color_model", "z_part_separation", "plates")).to eq(
        [
          {
            "plate_id" => 1, "name" => "Color region 1",
            "source_z_min" => 0.0, "source_z_max" => 0.5,
            "build_z_min" => 0.0, "build_z_max" => 0.5
          },
          {
            "plate_id" => 2, "name" => "Color region 2",
            "source_z_min" => 0.0, "source_z_max" => 0.7,
            "build_z_min" => 0.0, "build_z_max" => 0.7
          },
          {
            "plate_id" => 3, "name" => "Color region 3",
            "source_z_min" => 0.0, "source_z_max" => 0.9,
            "build_z_min" => 0.0, "build_z_max" => 0.9
          },
          {
            "plate_id" => 4, "name" => "Top White",
            "source_z_min" => 0.9, "source_z_max" => 2.14689422,
            "build_z_min" => 0.0, "build_z_max" => 1.24689422
          }
        ]
      )
      Zip::File.open(File.join(result.path, "lithop.3mf")) do |archive|
        model = archive.read("3D/3dmodel.model")
        expect(model).to include(
          'xmlns:BambuStudio="http://schemas.bambulab.com/package/2021"',
          'xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06"',
          'requiredextensions="p"',
          '<metadata name="Application">BambuStudio-02.08.03.66</metadata>',
          '<metadata name="BambuStudio:3mfVersion">1</metadata>',
          "<metadata name=\"lithop:Application\" preserve=\"1\">Lithop #{Lithop::VERSION}</metadata>"
        )
        expect(model.scan(%r{p:path="/3D/Objects/object_\d+\.model"}).length).to eq(10)
        expect(model.scan('printable="1"').length).to eq(4)
        expect(archive.map(&:name)).to include(
          "3D/_rels/3dmodel.model.rels",
          *Array.new(4) { |index| "3D/Objects/object_#{index + 1}.model" }
        )
        relationships = archive.read("3D/_rels/3dmodel.model.rels")
        expect(relationships.scan(%r{Target="/3D/Objects/object_\d+\.model"}).length).to eq(4)
        submodel = archive.read("3D/Objects/object_2.model")
        expect(submodel).to include(
          'xmlns:p="http://schemas.microsoft.com/3dmanufacturing/production/2015/06"',
          'requiredextensions="m p"'
        )
        expect(submodel.scan("p:UUID=")).not_to be_empty
        model_settings = archive.read("Metadata/model_settings.config")
        expect(model_settings.scan(%r{<metadata key="identify_id" value="(\d+)"/>}).flatten)
          .to eq(%w[218 253 276 287])
        expect(model_settings.scan(/subtype="normal_part" uuid="[^"]+"/).length).to eq(10)
        expect(model_settings.scan(/<assemble_item object_id="(\d+)" instance_id="0"/).flatten)
          .to eq(%w[4 8 12 14])
        expect(model_settings.scan(/<assemble_item object_id="\d+" volume_id="\d+"/).length).to eq(10)
        ranges = archive.read("Metadata/layer_config_ranges.xml")
        expect(ranges).to include('<object id="4">', 'min_z="0.1" max_z="1.24689422"')
      end
    end
  end

  it "recreates the same geometry and recipes independently of job identity" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      pixels = ([0, 255, 0] * 4).pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0)
      first = described_class.new(
        settings:,
        project_dir: directory,
        clock: instance_double("Clock", now: Time.utc(2026, 10, 6)),
        random: instance_double("Random", hex: "11111111")
      ).call(input)
      second = described_class.new(
        settings:,
        project_dir: directory,
        clock: instance_double("Clock", now: Time.utc(2026, 10, 7)),
        random: instance_double("Random", hex: "22222222")
      ).call(input)

      deterministic_files = %w[
        cmyk_white.stl preview.png transmission.png thickness.png cyan-mask.png magenta-mask.png
        yellow-mask.png white-mask.png settings.json PRINT_README.md
      ]
      deterministic_files.each do |name|
        expect(File.binread(File.join(first.path, name))).to eq(File.binread(File.join(second.path, name)))
      end

      first_manifest = JSON.parse(File.read(File.join(first.path, "manifest.json"))).except("job_id")
      second_manifest = JSON.parse(File.read(File.join(second.path, "manifest.json"))).except("job_id")
      expect(first_manifest).to eq(second_manifest)

      Zip::File.open(File.join(first.path, "lithop.3mf")) do |first_archive|
        Zip::File.open(File.join(second.path, "lithop.3mf")) do |second_archive|
          expect(first_archive.map(&:name)).to eq(second_archive.map(&:name))
          first_archive.each do |entry|
            expect(first_archive.read(entry.name)).to eq(second_archive.read(entry.name))
          end
        end
      end
    end
  end

  it "rejects an oversized physical CMYW mesh before writing the job" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "green.png")
      pixels = ([0, 255, 0] * 4).pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(
        width: 1.0,
        height: 1.0,
        pixel_size: 1.0,
        maximum_triangles: 20
      )
      exporter = described_class.new(settings:, project_dir: directory, clock:, random:)

      expect { exporter.call(input) }
        .to raise_error(Lithop::ConfigurationError, /physical CMYW mesh has 78 triangles/)
      expect(Dir).not_to exist(File.join(directory, "build", ".tmp-20261006T000000Z-12345678"))
    end
  end

  it "applies the triangle limit to the sum of all tile cut surfaces" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "green.png")
      pixels = ([0, 255, 0] * 2).pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 1, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(
        width: 2.0, height: 1.0, grid_columns: 2, grid_rows: 1,
        tile_count: 2, tile_layout: "columns", maximum_triangles: 100
      )
      exporter = described_class.new(settings:, project_dir: directory, clock:, random:)

      expect { exporter.call(input) }
        .to raise_error(Lithop::ConfigurationError, /physical CMYW tiled mesh has 156 triangles/)
      expect(Dir).not_to exist(File.join(directory, "build", ".tmp-20261006T000000Z-12345678"))
    end
  end

  it "cleans a failed temporary job without deleting the input image" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      pixels = [255, 0, 0, 255].pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 1, :uchar).pngsave(input)
      original = File.binread(input)
      settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0)
      exporter = described_class.new(settings:, project_dir: directory, clock:, random:)
      temporary = File.join(directory, "build", ".tmp-20261006T000000Z-12345678")
      destination = File.join(directory, "build", "20261006T000000Z-12345678")

      allow(Lithop::STL).to receive(:write).and_raise(Errno::ENOSPC)

      expect { exporter.call(input) }.to raise_error(Errno::ENOSPC)
      expect(File.binread(input)).to eq(original)
      expect(Dir).not_to exist(temporary)
      expect(Dir).not_to exist(destination)
    end
  end

  it "cleans a temporary job when generation is interrupted" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      exporter = described_class.new(
        settings: Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0),
        project_dir: directory,
        clock:,
        random:
      )
      temporary = File.join(directory, "build", ".tmp-20261006T000000Z-12345678")

      allow(Lithop::STL).to receive(:write).and_raise(Interrupt)

      expect { exporter.call(input) }.to raise_error(Interrupt)
      expect(File).to exist(input)
      expect(Dir).not_to exist(temporary)
      status = JSON.parse(
        File.read(File.join(directory, "build", ".jobs", "20261006T000000Z-12345678.json"))
      )
      expect(status).to include("state" => "cancelled", "phase" => "cancelled")
    end
  end

  it "honors a cancellation request and does not publish an incomplete job" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      job_id = "cancel-request"
      progress = lambda do |event|
        next unless event.phase == "image_processing"

        Lithop::JobExecution.request_cancel(project_dir: directory, job_id:)
      end
      exporter = described_class.new(
        settings: Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0),
        project_dir: directory,
        job_progress: progress,
        job_id:
      )

      expect { exporter.call(input) }.to raise_error(Lithop::JobCancelled)
      expect(Dir).not_to exist(File.join(directory, "build", job_id))
      expect(Dir).not_to exist(File.join(directory, "build", ".tmp-#{job_id}"))
      status = JSON.parse(File.read(File.join(directory, "build", ".jobs", "#{job_id}.json")))
      expect(status.fetch("state")).to eq("cancelled")
    end
  end

  it "refuses a colliding job ID without overwriting the completed job or input" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      original = File.binread(input)
      job_id = "20261006T000000Z-12345678"
      destination = File.join(directory, "build", job_id)
      FileUtils.mkdir_p(destination)
      sentinel = File.join(destination, "manifest.json")
      File.write(sentinel, "keep")
      exporter = described_class.new(
        settings: Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0),
        project_dir: directory,
        clock:,
        random:
      )

      expect { exporter.call(input) }.to raise_error(Lithop::Error, /output already exists/)
      expect(File.read(sentinel)).to eq("keep")
      expect(File.binread(input)).to eq(original)
      expect(Dir).not_to exist(File.join(directory, "build", ".tmp-#{job_id}"))
    end
  end

  it "preserves a colliding temporary job owned by another run" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      job_id = "20261006T000000Z-12345678"
      temporary = File.join(directory, "build", ".tmp-#{job_id}")
      FileUtils.mkdir_p(temporary)
      sentinel = File.join(temporary, "owner.txt")
      File.write(sentinel, "keep")
      exporter = described_class.new(
        settings: Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0),
        project_dir: directory,
        clock:,
        random:
      )

      expect { exporter.call(input) }.to raise_error(Lithop::Error, /output already exists/)
      expect(File.read(sentinel)).to eq("keep")
    end
  end

  it "records comparison layer structure in every generated artifact" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      settings = Lithop::Settings.new(
        width: 2.0,
        height: 2.0,
        pixel_size: 1.0,
        minimum_thickness: 0.95,
        layer_height: 0.10,
        color_layer_count: 5,
        pigment_order: %i[yellow magenta cyan]
      )
      result = described_class.new(settings:, project_dir: directory, clock:, random:).call(input)

      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      expect(manifest.dig("color_model", "color_layer_count")).to eq(5)
      expect(manifest.dig("color_model", "pigment_order")).to eq(%w[yellow magenta cyan])
      expect(manifest.dig("color_model", "color_layer_sequence")).to eq(%w[yellow magenta cyan white])
      expect(manifest.dig("color_model", "minimum_top_white_layers")).to eq(0)
      expect(manifest.dig("color_model", "thickness_mm", "minimum_total")).to eq(1.0)
      expect(manifest.dig("color_model", "recipe_summaries")).to include(
        hash_including("counts" => { "cyan" => 1, "magenta" => 1, "yellow" => 1, "white" => 2 })
      )

      print_readme = File.read(File.join(result.path, "PRINT_README.md"))
      expect(print_readme).to include("5 CMY/W color layers")
      expect(print_readme).to include("Yellow -> Magenta -> Cyan -> White")
    end
  end

  it "exports the reference layout as a Bambu CMYW project without an outer frame" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      pixels = ([0, 0, 255] * 9).pack("C*")
      Vips::Image.new_from_memory(pixels, 3, 3, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(
        layout_profile: "standard",
        width: 2.0, height: 2.0, grid_columns: 2, grid_rows: 2
      )

      result = described_class.new(settings:, project_dir: directory, clock:, random:).call(input)
      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      report = Lithop::ReferenceThreeMF.new(File.join(result.path, "lithop.3mf")).call

      expect(manifest.fetch("dimensions_mm")).to eq(
        "width" => 2.0, "height" => 2.0, "depth" => 2.14689422
      )
      expect(manifest.dig("color_model", "layout_profile")).to eq("standard")
      assembly_id = report.fetch(:models).flat_map { |model| model.fetch(:objects) }
                          .find { |object| object.fetch(:components).positive? }.fetch(:id)
      expect(report.fetch(:plates)).to eq([{ id: 1, name: "lithophane", object_ids: [assembly_id] }])
      expect(report.fetch(:parts).map { |part| part.fetch(:name) }.join(" ")).not_to match(/Black|margin|frame/i)
      expect(report.fetch(:parts).map { |part| part.fetch(:extruder) }).to all(be_between(1, 4))
    end
  end

  it "applies and snapshots a complete measured calibration profile" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "cyan.png")
      Vips::Image.new_from_memory(([0, 255, 255] * 4).pack("C*"), 2, 2, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0)
      profile = measured_calibration_profile(settings, profile_id: "measured-export") do |candidate|
        patches = candidate.data.fetch("patches")
        cyan = patches.find { |patch| patch.dig("recipe", "cyan") == 5 }
        magenta = patches.find { |patch| patch.dig("recipe", "magenta") == 5 }
        cyan.fetch("measurements").first["transmitted_srgb"] = [1.0, 0.0, 1.0]
        magenta.fetch("measurements").first["transmitted_srgb"] = [0.0, 1.0, 1.0]
      end
      profile_path = File.join(directory, "measured.json")
      profile.write(profile_path)
      calibration = described_class::CalibrationInput.new(profile:, path: profile_path)

      result = described_class.new(
        settings:,
        project_dir: directory,
        calibration:,
        clock:,
        random:
      ).call(input)

      manifest = JSON.parse(File.read(File.join(result.path, "manifest.json")))
      recorded_settings = JSON.parse(File.read(File.join(result.path, "settings.json")))
      readme = File.read(File.join(result.path, "PRINT_README.md"))
      stl_maximum_z = Lithop::STL.each_triangle(File.join(result.path, "cmyk_white.stl"))
                                 .flat_map { |triangle| triangle.map { |vertex| vertex.fetch(2) } }.max
      three_mf = Lithop::ReferenceThreeMF.new(File.join(result.path, "lithop.3mf")).call
      white_part = three_mf.fetch(:parts).find { |part| part.fetch(:name).include?("White") }
      white_object = three_mf.fetch(:models).flat_map { |model| model.fetch(:objects) }
                             .find { |object| object.fetch(:id) == white_part.fetch(:id) }
      thickness = Vips::Image.new_from_file(File.join(result.path, "thickness.png"))
      expect(manifest.dig("color_model", "calibration", "profile_id")).to eq("measured-export")
      expect(manifest.dig("color_model", "luminance_control", "method")).to eq("measured_white_luminance")
      expect(manifest.dig("color_model", "preview", "calibration_profile_id")).to eq("measured-export")
      expect(manifest.dig("color_model", "recipe_summaries")).to include(
        hash_including("counts" => { "cyan" => 0, "magenta" => 5, "yellow" => 0, "white" => 2 })
      )
      expect(recorded_settings.fetch("calibration_profile_id")).to eq("measured-export")
      expect(recorded_settings.fetch("calibration_profile_path")).to eq(profile_path)
      expect(File).to exist(File.join(result.path, "calibration-profile.json"))
      expect(readme).to include("Measured calibration profile: measured-export")
      expect(stl_maximum_z).to be_within(1e-6).of(1.32)
      expect(white_object.fetch(:maximum).fetch(2)).to be_within(1e-6).of(1.32)
      expect(thickness.getpoint(0, 0).first).to eq(71.0)
    end
  end
end

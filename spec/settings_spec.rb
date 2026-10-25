# frozen_string_literal: true

RSpec.describe Lithop::Settings do
  describe "layout profiles" do
    it "uses the standard seven-layer CMYW defaults" do
      settings = described_class.new

      expect(settings.layout_profile).to eq("standard")
      expect([settings.width, settings.height]).to eq([140.0, 104.0])
      expect([settings.columns, settings.rows]).to eq([637, 473])
      expect(settings.pixel_size_x).to be_within(1e-9).of(140.0 / 637)
      expect(settings.pixel_size_y).to be_within(1e-9).of(104.0 / 473)
      expect(settings.x_boundaries.last).to eq(140.0)
      expect(settings.y_boundaries.last).to eq(104.0)
      expect(settings.maximum_thickness).to eq(1.94)
      expect(settings.minimum_thickness).to eq(0.74)
      expect(settings.effective_minimum_thickness).to eq(0.74)
      expect(settings.effective_maximum_thickness).to eq(1.94)
      expect(settings.base_white_layers).to eq(1)
      expect(settings.layer_structure.top_layer_height).to eq(0.08)
      expect(settings.layer_structure.top_white_layer_count(settings.effective_minimum_thickness)).to eq(1)
      expect(settings.bambu_project).to be(true)
    end

    it "lets explicit settings override standard defaults" do
      settings = described_class.new(layout_profile: "standard", width: 100.0, height: 130.0)

      expect([settings.width, settings.height]).to eq([100.0, 130.0])
      expect([settings.grid_columns, settings.grid_rows]).to eq([nil, nil])
      expect([settings.columns, settings.rows]).to eq([455, 591])
    end

    it "rejects removed layout profiles" do
      expect { described_class.new(layout_profile: "legacy") }
        .to raise_error(Lithop::ConfigurationError, /layout_profile must be one of: standard/)
    end
  end

  describe "nozzle diameter" do
    it "uses 0.2 mm by default and accepts 0.4 mm" do
      expect(described_class.new.nozzle_diameter).to eq(0.2)
      expect(described_class.new(nozzle_diameter: 0.4).nozzle_diameter).to eq(0.4)
    end

    it "rejects unsupported nozzle diameters" do
      expect { described_class.new(nozzle_diameter: 0.6) }
        .to raise_error(Lithop::ConfigurationError, /nozzle_diameter must be one of: 0.2, 0.4/)
    end
  end

  describe "tile layout" do
    it "defaults to one tile and resolves explicit row, column, and grid layouts" do
      expect(described_class.new.resolved_tile_shape).to eq([1, 1])
      expect(described_class.new(tile_count: 3, tile_layout: "columns").resolved_tile_shape).to eq([1, 3])
      expect(described_class.new(tile_count: 3, tile_layout: "rows").resolved_tile_shape).to eq([3, 1])
      grid = described_class.new(tile_count: 6, tile_layout: "grid", tile_rows: 2, tile_columns: 3)
      expect(grid.resolved_tile_shape).to eq([2, 3])
    end

    it "rejects invalid counts, layouts, grids, and zero-cell tiles" do
      expect { described_class.new(tile_count: 0) }
        .to raise_error(Lithop::ConfigurationError, /tile_count must be a positive integer/)
      expect { described_class.new(tile_layout: "diagonal") }
        .to raise_error(Lithop::ConfigurationError, /tile_layout must be one of/)
      expect { described_class.new(tile_count: 6, tile_layout: "grid", tile_rows: 2, tile_columns: 2) }
        .to raise_error(Lithop::ConfigurationError, /must equal tile_count/)
      expect { described_class.new(tile_count: 2, tile_rows: 1) }
        .to raise_error(Lithop::ConfigurationError, /only be set for grid layout/)
      expect do
        described_class.new(
          width: 2.0, height: 2.0, grid_columns: 2, grid_rows: 2,
          tile_count: 3, tile_layout: "columns"
        )
      end.to raise_error(Lithop::ConfigurationError, /at least one XY cell/)
    end
  end

  describe "Z-part separation" do
    it "uses a 0.1 mm first layer, 0.08 mm pitch, equal source slices, and one top White layer" do
      settings = described_class.new(separate_z_parts: true, color_region_parts: 3)

      expect(settings.separate_z_parts).to be(true)
      expect(settings.color_region_parts).to eq(3)
      expect(settings.color_layer_count).to eq(8)
      expect(settings.first_layer_height).to eq(0.1)
      expect(settings.layer_height).to eq(0.08)
      expect(settings.resolved_z_part_count).to eq(3)
      expect(settings.layer_structure.top_layer_height).to eq(0.08)
      expect(settings.layer_structure.top_white_start).to eq(0.74)
      expect(settings.effective_minimum_thickness).to eq(0.82)
      expect(settings.effective_maximum_thickness).to eq(1.94)
      expect(settings.z_separated_minimum_thickness).to eq(0.96)
      expect(settings.z_separated_source_end).to eq(1.06)
      expect(settings.z_part_base_white_thickness).to eq(0.1)
      expect(settings.z_part_base_white_layers_by_plate).to eq([1, 1, 3])
      expect(settings.z_part_base_white_thicknesses).to eq([0.1, 0.1, 0.26])
      expect(settings.z_part_minimum_build_thickness).to eq(0.34)
      expect(settings.z_separated_output_minimum_thickness).to eq(1.18)
      expect(settings.z_separated_output_maximum_thickness).to eq(2.3)
      expect(settings.resolved_z_part_boundaries).to eq([0.1, 0.42, 0.74, 1.06])
      expect(settings.resolved_z_part_ranges).to eq([0.1...0.42, 0.42...0.74, 0.74...1.06])
      expect(settings.resolved_z_color_ranges).to eq([0.1...0.42, 0.42...0.74, 0.74...0.74])
    end

    it "rejects invalid separation values" do
      expect { described_class.new(separate_z_parts: "yes") }
        .to raise_error(Lithop::ConfigurationError, /separate_z_parts must be a boolean/)
      expect { described_class.new(color_region_parts: 0) }
        .to raise_error(Lithop::ConfigurationError, /color_region_parts must be an integer/)
      expect { described_class.new(color_region_parts: 4) }
        .to raise_error(Lithop::ConfigurationError, /color_region_parts must be an integer/)
    end

    it "requires enough maximum thickness for the requested separated plates" do
      expect do
        described_class.new(
          separate_z_parts: true,
          minimum_thickness: 0.9,
          maximum_thickness: 1.0,
          top_white_start: 0.9
        )
      end.to raise_error(Lithop::ConfigurationError, /maximum_thickness of at least 1.06 mm/)
    end
  end

  describe "color model" do
    it "uses CMY by default" do
      expect(described_class.new.color_model).to eq("cmy")
    end

    it "rejects unsupported color models" do
      expect { described_class.new(color_model: "rgb") }
        .to raise_error(Lithop::ConfigurationError, /color_model must be one of: cmy/)
    end
  end

  describe "comparison layer structure" do
    it "uses seven color layers in yellow, magenta, cyan order by default" do
      settings = described_class.new

      expect(settings.color_layer_count).to eq(7)
      expect(settings.pigment_order).to eq(%i[yellow magenta cyan])
    end

    it "accepts a four-layer comparison with a reversed pigment order" do
      settings = described_class.new(
        color_layer_count: 4,
        pigment_order: "yellow,magenta,cyan",
        minimum_thickness: 0.99
      )

      expect(settings.color_layer_count).to eq(4)
      expect(settings.pigment_order).to eq(%i[yellow magenta cyan])
    end

    it "accepts all six pigment stacking orders" do
      expect(described_class::PIGMENT_ORDERS.map { |order| described_class.new(pigment_order: order).pigment_order })
        .to eq(described_class::PIGMENT_ORDERS)
    end

    it "rejects an incomplete or repeated pigment order" do
      expect { described_class.new(pigment_order: "cyan,magenta,magenta") }
        .to raise_error(Lithop::ConfigurationError, /pigment_order must contain/)
    end

    it "requires a physical minimum thickness for the selected layer structure" do
      expect do
        described_class.new(minimum_thickness: 0.99, maximum_thickness: 1.01)
      end.to raise_error(Lithop::ConfigurationError, /no printable layer boundary/)
    end
  end

  describe "layer boundaries" do
    it "rounds requested limits to printable boundaries" do
      settings = described_class.new(width: 2.0, height: 1.0, pixel_size: 1.0)

      expect(settings.effective_minimum_thickness).to be_within(0.001).of(0.74)
      expect(settings.effective_maximum_thickness).to be_within(0.001).of(1.94)
      expect(settings.columns).to eq(2)
      expect(settings.rows).to eq(1)
    end

    it "keeps a partial cell at each non-divisible outer edge" do
      settings = described_class.new(width: 2.5, height: 1.25, pixel_size: 1.0)

      expect([settings.columns, settings.rows]).to eq([3, 2])
      expect(settings.x_boundaries).to eq([0.0, 1.0, 2.0, 2.5])
      expect(settings.y_boundaries).to eq([0.0, 1.0, 1.25])
    end

    it "rejects a range without a printable boundary" do
      expect do
        described_class.new(minimum_thickness: 0.83, maximum_thickness: 0.85)
      end.to raise_error(Lithop::ConfigurationError, /no printable layer boundary/)
    end
  end

  describe "image margins" do
    it "uses no margins by default and rounds requested margins to image samples" do
      settings = described_class.new(
        width: 10.0,
        height: 8.0,
        pixel_size: 0.5,
        margin_top: 1.0,
        margin_right: 1.5,
        margin_bottom: 0.5,
        margin_left: 2.0
      )

      expect(described_class.new.margin_samples).to eq(top: 0, right: 0, bottom: 0, left: 0)
      expect(settings.margin_samples).to eq(top: 2, right: 3, bottom: 1, left: 4)
    end

    it "rejects negative margins and margins that consume the image area" do
      expect { described_class.new(margin_left: -0.1) }
        .to raise_error(Lithop::ConfigurationError, /margin_left must be a non-negative finite number/)
      expect { described_class.new(width: 2.0, margin_left: 1.0, margin_right: 1.0) }
        .to raise_error(Lithop::ConfigurationError, /must each leave image area/)
    end
  end
  describe "image placement" do
    it "uses a centered cover without extra zoom by default" do
      settings = described_class.new

      expect(settings.image_fit).to eq("cover")
      expect(settings.crop_position_x).to eq(0.5)
      expect(settings.crop_position_y).to eq(0.5)
      expect(settings.crop_scale).to eq(1.0)
    end

    it "accepts contain placement and explicit crop controls" do
      settings = described_class.new(
        image_fit: "contain", crop_position_x: 0.0, crop_position_y: 1.0, crop_scale: 0.75
      )

      expect(settings.image_fit).to eq("contain")
      expect(settings.crop_position_x).to eq(0.0)
      expect(settings.crop_position_y).to eq(1.0)
      expect(settings.crop_scale).to eq(0.75)
    end

    it "rejects unknown fit modes and out-of-range crop controls" do
      expect { described_class.new(image_fit: "stretch") }
        .to raise_error(Lithop::ConfigurationError, /image_fit must be one of: cover, contain/)
      expect { described_class.new(crop_position_x: -0.1) }
        .to raise_error(Lithop::ConfigurationError, /crop_position_x must be a finite number from 0 to 1/)
      expect { described_class.new(crop_position_y: 1.1) }
        .to raise_error(Lithop::ConfigurationError, /crop_position_y must be a finite number from 0 to 1/)
      expect { described_class.new(crop_scale: 0.0) }
        .to raise_error(Lithop::ConfigurationError, /crop_scale must be a finite number greater than 0/)
    end
  end

  describe "image adjustments" do
    it "uses neutral percentages by default and accepts the full adjustment range" do
      expect(described_class.new.to_h.values_at(:brightness, :contrast, :saturation)).to eq([0.0, 0.0, 0.0])
      expect(described_class.new.suppress_pale_colors).to be(false)
      expect(described_class.new.to_h.values_at(:yellow_mix_color, :yellow_mix_percent)).to eq(["cyan", 0.0])

      settings = described_class.new(
        brightness: -100.0, contrast: 25.0, saturation: 100.0, suppress_pale_colors: true,
        yellow_mix_color: "magenta", yellow_mix_percent: 20.0
      )
      expect(settings.to_h.values_at(:brightness, :contrast, :saturation)).to eq([-100.0, 25.0, 100.0])
      expect(settings.suppress_pale_colors).to be(true)
      expect(settings.to_h.values_at(:yellow_mix_color, :yellow_mix_percent)).to eq(["magenta", 20.0])
    end

    it "rejects non-finite and out-of-range adjustment percentages" do
      expect { described_class.new(brightness: -100.1) }
        .to raise_error(Lithop::ConfigurationError, /brightness must be a finite percentage from -100 to 100/)
      expect { described_class.new(contrast: Float::INFINITY) }
        .to raise_error(Lithop::ConfigurationError, /contrast must be a finite percentage from -100 to 100/)
      expect { described_class.new(saturation: 100.1) }
        .to raise_error(Lithop::ConfigurationError, /saturation must be a finite percentage from -100 to 100/)
      expect { described_class.new(suppress_pale_colors: "false") }
        .to raise_error(Lithop::ConfigurationError, /suppress_pale_colors must be a boolean/)
      expect { described_class.new(yellow_mix_color: "yellow") }
        .to raise_error(Lithop::ConfigurationError, /yellow_mix_color must be one of: cyan, magenta/)
      expect { described_class.new(yellow_mix_percent: -0.1) }
        .to raise_error(Lithop::ConfigurationError, /yellow_mix_percent must be a finite percentage from 0 to 100/)
      expect { described_class.new(yellow_mix_percent: 100.1) }
        .to raise_error(Lithop::ConfigurationError, /yellow_mix_percent must be a finite percentage from 0 to 100/)
    end
  end

  describe "color cells" do
    it "uses the thickness pixel size unless a separate color size is selected" do
      expect(described_class.new.color_pixel_size).to be_nil
      expect(described_class.new(pixel_size: 0.5).effective_color_pixel_size).to eq(0.5)
      expect(described_class.new(pixel_size: 0.5, color_pixel_size: 0.8).effective_color_pixel_size).to eq(0.8)
    end

    it "rejects a non-positive separate color size" do
      expect { described_class.new(color_pixel_size: 0.0) }
        .to raise_error(Lithop::ConfigurationError, /color_pixel_size must be a positive finite number or null/)
      expect { described_class.new(pixel_size: 0.5, color_pixel_size: 0.25) }
        .to raise_error(Lithop::ConfigurationError, /color_pixel_size must be greater than or equal to pixel_size/)
    end
  end

  describe "mesh limits" do
    it "suggests a coarser pixel size when the estimated mesh is too large" do
      expect do
        described_class.new(width: 10.0, height: 10.0, pixel_size: 0.1, maximum_triangles: 1_000)
      end.to raise_error(
        Lithop::ConfigurationError,
        %r{estimated STL mesh has .* Increase pixel_size to about .* or reduce width/height}
      )
    end
  end
end

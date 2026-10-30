# frozen_string_literal: true

require "json"
require "lithop/cli/settings"
require "lithop/web/settings_form"

RSpec.describe Lithop::Web::SettingsForm do
  it "merges project defaults with validated browser settings" do
    Dir.mktmpdir do |project_dir|
      FileUtils.mkdir_p(File.join(project_dir, "config"))
      File.write(
        File.join(project_dir, "config", "settings.json"),
        JSON.generate(width: 80.0, height: 60.0, pixel_size: 0.4, saturation: 12.0)
      )
      form = described_class.new(project_dir:)

      settings = form.resolve(
        "width" => "100", "height" => "70", "pixel_size" => "0.5",
        "brightness" => "15", "tile_count" => "2", "tile_layout" => "columns",
        "yellow_mix_color" => "magenta", "yellow_mix_percent" => "20",
        "pigment_order" => "cyan,yellow,magenta",
        "suppress_pale_colors" => "1", "separate_z_parts" => "1"
      )

      expect(settings).to have_attributes(
        width: 100.0, height: 70.0, pixel_size: 0.5, brightness: 15.0,
        saturation: 12.0, suppress_pale_colors: true,
        yellow_mix_color: "magenta", yellow_mix_percent: 20.0,
        pigment_order: %i[cyan yellow magenta],
        tile_count: 2, tile_layout: "columns", separate_z_parts: true
      )
      expect(settings.grid_columns).to be_nil
      expect(settings.tile_rows).to be_nil
      expect(settings.tile_columns).to be_nil
    end
  end

  it "reports invalid numeric form values as configuration errors" do
    Dir.mktmpdir do |project_dir|
      form = described_class.new(project_dir:)

      expect { form.resolve("width" => "wide") }
        .to raise_error(Lithop::ConfigurationError, /valid numbers/)
    end
  end

  it "resolves browser fields to the same settings as CLI overrides" do
    Dir.mktmpdir do |project_dir|
      FileUtils.mkdir_p(File.join(project_dir, "config"))
      File.write(
        File.join(project_dir, "config", "settings.json"),
        JSON.generate(pixel_size: 0.25, minimum_thickness: 1.0, maximum_thickness: 2.1)
      )
      overrides = {
        width: 90.0, height: 70.0, brightness: 8.0, contrast: -3.0, saturation: 11.0,
        suppress_pale_colors: false, yellow_mix_color: "magenta", yellow_mix_percent: 15.0,
        pigment_order: "cyan,yellow,magenta",
        tile_count: 4, tile_layout: "grid", tile_rows: 2, tile_columns: 2,
        separate_z_parts: true, color_region_parts: 3
      }
      browser_params = overrides.transform_keys(&:to_s).transform_values(&:to_s)
      browser_params["separate_z_parts"] = "1"
      browser_params.delete("suppress_pale_colors")

      web_settings = described_class.new(project_dir:).resolve(browser_params)
      cli_settings = Lithop::CLISettings.new(cwd: project_dir).call(overrides).settings

      expect(web_settings.to_h).to eq(cli_settings.to_h)
    end
  end
end

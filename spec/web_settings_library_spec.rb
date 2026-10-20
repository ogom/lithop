# frozen_string_literal: true

require "json"
require "tmpdir"
require "lithop/web/app"

RSpec.describe Lithop::Web::SettingsLibrary do
  it "persists versioned presets and a draft without inputs or output paths" do
    Dir.mktmpdir do |project_dir|
      library = described_class.new(project_dir:, clock: -> { Time.utc(2026, 10, 18) })
      values = { "width" => "120", "height" => "90", "brightness" => "5", "image" => "secret.png",
                 "job_id" => "private-job", "output_path" => "/tmp/private" }

      library.save_preset("fine line", values)
      library.save_draft(values.merge("width" => "130"))
      restored = described_class.new(project_dir:).read
      stored = JSON.parse(File.read(File.join(project_dir, "config", "ui-settings.json")))

      expect(restored).to include("schema_version" => 1)
      expect(restored.dig("presets", "fine line", "settings")).to include("width" => 120.0, "height" => 90.0)
      expect(restored.dig("draft", "settings", "width")).to eq(130.0)
      expect(stored.to_s).not_to include("secret.png", "private-job", "/tmp/private")
      expect(File).not_to exist(File.join(project_dir, "config", "settings.json"))
    end
  end

  it "renames and deletes presets and explains incompatible saved fields" do
    Dir.mktmpdir do |project_dir|
      library = described_class.new(project_dir:)
      library.save_preset("old", "width" => "120")
      library.rename_preset("old", "new")
      expect(library.read.fetch("presets")).to have_key("new")
      library.delete_preset("new")
      expect(library.read.fetch("presets")).to be_empty

      path = File.join(project_dir, "config", "ui-settings.json")
      File.write(path, JSON.generate(schema_version: 1, presets: { bad: { settings: { future: 1 } } }))
      expect { library.read }.to raise_error(Lithop::InputError, /unsupported saved settings: future/)
    end
  end
end

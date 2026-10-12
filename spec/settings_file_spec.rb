# frozen_string_literal: true

require "json"

RSpec.describe Lithop::SettingsFile do
  it "loads known settings and accepts an omitted schema version" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "settings.json")
      File.write(
        path,
        JSON.generate(pixel_size: 0.5, color_model: "CMY", margin_left: 2.0, image_fit: "CONTAIN")
      )

      result = described_class.load(path, required: true)

      expect(result.path).to eq(path)
      expect(result.values).to eq(
        pixel_size: 0.5, color_model: "cmy", margin_left: 2.0, image_fit: "contain"
      )
    end
  end

  it "uses no overrides when the default settings file is absent" do
    Dir.mktmpdir do |directory|
      result = described_class.load(File.join(directory, "missing.json"))

      expect(result.path).to be_nil
      expect(result.values).to be_empty
    end
  end

  it "rejects unknown keys" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "settings.json")
      File.write(path, JSON.generate(unknown: true))

      expect { described_class.load(path, required: true) }
        .to raise_error(Lithop::ConfigurationError, /unknown keys: unknown/)
    end
  end

  it "rejects unsupported schema versions" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "settings.json")
      File.write(path, JSON.generate(schema_version: 2))

      expect { described_class.load(path, required: true) }
        .to raise_error(Lithop::ConfigurationError, /unsupported settings schema_version 2/)

      File.write(path, JSON.generate(schema_version: 1.0))
      expect { described_class.load(path, required: true) }
        .to raise_error(Lithop::ConfigurationError, /unsupported settings schema_version 1.0/)
    end
  end

  it "rejects invalid JSON and non-object roots" do
    Dir.mktmpdir do |directory|
      invalid = File.join(directory, "invalid.json")
      array = File.join(directory, "array.json")
      File.write(invalid, "{")
      File.write(array, "[]")

      expect { described_class.load(invalid, required: true) }
        .to raise_error(Lithop::ConfigurationError, /not valid JSON/)
      expect { described_class.load(array, required: true) }
        .to raise_error(Lithop::ConfigurationError, /must contain a JSON object/)
    end
  end
end

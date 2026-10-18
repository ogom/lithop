# frozen_string_literal: true

require "tempfile"
require "lithop/web/preview_store"

RSpec.describe Lithop::Web::PreviewStore do
  it "stages an allowed input under an opaque ID and discards only that input" do
    Dir.mktmpdir do |project_dir|
      input = Tempfile.new(["input", ".png"])
      input.write("image")
      input.rewind
      random = instance_double("Random", hex: "a" * 32)
      store = described_class.new(project_dir:, random:)

      preview_id = store.stage(upload: input, filename: "photo.png")
      staged = store.with_input(preview_id) { |path, filename| [File.binread(path), filename] }

      expect(preview_id).to eq("a" * 32)
      expect(staged).to eq(["image", "photo.png"])
      expect(store.discard(preview_id)).to be(true)
      expect { store.with_input(preview_id) { nil } }.to raise_error(Lithop::InputError, /not found/)
    ensure
      input&.close!
    end
  end

  it "rejects unsupported extensions before creating preview data" do
    Dir.mktmpdir do |project_dir|
      input = StringIO.new("data")
      store = described_class.new(project_dir:)

      expect { store.stage(upload: input, filename: "input.pdf") }
        .to raise_error(Lithop::InputError, /JPEG, PNG, or SVG/)
    end
  end
end

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

  it "caches rendered previews by normalized settings key" do
    Dir.mktmpdir do |project_dir|
      input = StringIO.new("image")
      random = instance_double("Random", hex: "b" * 32)
      store = described_class.new(project_dir:, random:)
      preview_id = store.stage(upload: input, filename: "photo.png")
      calls = 0

      first = store.render(preview_id, "c" * 64) do
        calls += 1
        "rendered"
      end
      second = store.render(preview_id, "c" * 64) do
        calls += 1
        "changed"
      end

      expect(first).to eq(["rendered", false])
      expect(second).to eq(["rendered", true])
      expect(calls).to eq(1)
    end
  end

  it "keeps only the newest bounded set of rendered previews" do
    Dir.mktmpdir do |project_dir|
      random = instance_double("Random", hex: "d" * 32)
      store = described_class.new(project_dir:, random:)
      preview_id = store.stage(upload: StringIO.new("image"), filename: "photo.png")

      10.times do |index|
        store.render(preview_id, index.to_s(16).rjust(64, "0")) { "rendered-#{index}" }
      end
      cache_files = Dir.glob(File.join(project_dir, "build", ".previews", preview_id, "render-*.png"))

      expect(cache_files.length).to eq(8)
      expect(cache_files).to include(end_with("#{9.to_s(16).rjust(64, "0")}.png"))
    end
  end
end

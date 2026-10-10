# frozen_string_literal: true

require "digest"
require "json"
require "vips"
require "zip"

RSpec.describe "export artifact contract" do
  let(:binary_digests) do
    {
      "PRINT_README.md" => "3728f87b8240309b584a3a72cb0d8e184895f62b7b0b9166ec48b4ee954eda0a",
      "cmyk_white.stl" => "00457d950383f8e76ea3eee0591ee76bc3ac1339dd0bac9b6e42f4d87ba63fed"
    }
  end
  let(:preview_digests) do
    {
      "preview.png" => "94ea0e744ef0604cad2e079968f47a18e5090f6a791610672ec455bef716c775",
      "transmission.png" => "4895125682cdf764b1e35a23d67e4e5b2c46ef7465296390da1cd6f73188aba7",
      "thickness.png" => "577f694540522ff36e8c62fc6cbf1b7a3caa0c97ce1c7ba1ea57ceee9b9463e4",
      "cyan-mask.png" => "90c7c46516e6ba1db4c4a66f9dc8328edcbfa617a10d7c95f66daf2d79aae002",
      "magenta-mask.png" => "9e57e1386a3254ea1a550c659997f550d3f0ae743d7f98c55e7c3c7bf67f10f3",
      "yellow-mask.png" => "73d03c6e3d4d655d31bee8463fc777a681a23d5733232fa8671a32437270aaaa",
      "white-mask.png" => "4bdf8079799c85fc3fe31323208745348156269b8968ebaa89874ed46aa5f608"
    }
  end
  let(:three_mf_digests) do
    {
      "3D/3dmodel.model" => "55b3323fd7497d0b1e8795a23cd5d49a3f967a82f26edf162fa14e19cc88443c",
      "Metadata/layer_config_ranges.xml" => "a95116fadd7522bf5d6d744d3fad15b7014fb28c0553e364cc2b673f5903e42a",
      "Metadata/model_settings.config" => "a7708caa8f6338c088b6cc50211499c94cc37ca5b7e2fdae6b1297187cee8572",
      "Metadata/project_settings.config" => "9f974735b67357579d32abfe31afc5254e70b9eaf999167c0caea7eb883e3e21",
      "[Content_Types].xml" => "70272308f051681b28d6ec150ef3b3a2d2f94e2a6f3ba55da935bdca965c439a",
      "_rels/.rels" => "fe78c4cf56b0257a22e9883fa3e3fbfe5cea998fd18e1254f6eb28c3f34641c7"
    }
  end

  it "matches the recorded CMYW, margin, mesh, metadata, and preview baseline" do
    Dir.mktmpdir do |project_dir|
      input = File.join(project_dir, "input.png")
      pixels = [0, 255, 255, 255, 0, 255, 255, 255, 0, 255, 255, 255].pack("C*")
      Vips::Image.new_from_memory(pixels, 2, 2, 3, :uchar).pngsave(input)
      settings = Lithop::Settings.new(
        width: 4.0, height: 4.0, pixel_size: 1.0,
        margin_top: 1.0, margin_right: 1.0, margin_bottom: 1.0, margin_left: 1.0
      )
      result = Lithop::Export.new(
        settings:, project_dir:,
        clock: instance_double("Clock", now: Time.utc(2026, 10, 6)),
        random: instance_double("Random", hex: "12345678")
      ).call(input)

      binary_digests.each do |name, digest|
        expect(Digest::SHA256.file(File.join(result.path, name)).hexdigest).to eq(digest), name
      end
      preview_digests.each do |name, digest|
        preview = Vips::Image.new_from_file(File.join(result.path, name))
        expect([preview.width, preview.height]).to eq([4, 4]), name
        expect(Digest::SHA256.hexdigest(preview.write_to_memory)).to eq(digest), name
      end
      expect(normalized_json_digest(result.path, "settings.json", "input_path"))
        .to eq("cfe90f601b0290c6e6a72c022213b0c335ad97541c1f9e6389fb4e93e3851ddd")
      expect(normalized_json_digest(result.path, "manifest.json", "job_id"))
        .to eq("38497c73701f04bec499bc91ee26df17f4b900a0502c9950f8001ee3dddec839")
      expect(archive_digests(result.path)).to eq(three_mf_digests)
    end
  end

  def normalized_json_digest(path, name, excluded_key)
    data = JSON.parse(File.read(File.join(path, name)))
    data.delete(excluded_key)
    Digest::SHA256.hexdigest(JSON.generate(data))
  end

  def archive_digests(path)
    Zip::File.open(File.join(path, "lithop.3mf")) do |archive|
      archive.sort_by(&:name).to_h do |entry|
        [entry.name, Digest::SHA256.hexdigest(archive.read(entry.name))]
      end
    end
  end
end

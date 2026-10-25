# frozen_string_literal: true

require "digest"
require "json"
require "vips"
require "zip"

RSpec.describe "export artifact contract" do
  let(:binary_digests) do
    {
      "PRINT_README.md" => "09ea28717af95187615cc261d965512e0b677745abe454423c052b40a5a056c2",
      "cmyk_white.stl" => "a454bc5957122c39c1e84ba3f391f13e8818731b80d92a2d6ceb1318ef6fe855"
    }
  end
  let(:preview_digests) do
    {
      "preview.png" => "d0a43958a12e89ac7c7a0dabd0402f60c1cd7d2b00ce087c257d7823c89d5603",
      "transmission.png" => "c629a96f796703dec3c64a725f8c77552ef3f8fb7a7b673664a30ae07cf15310",
      "thickness.png" => "97bbb11276b5a9610105a39a4d194c0e9be58b3567ded38e72aa0a2f734801b4",
      "cyan-mask.png" => "a52ef9aeb6c771d9b12eb5247c1f5f7c77c54c321d12ad44cc584c5865886c78",
      "magenta-mask.png" => "cf8e73d8e8b46bbb4eee01b152f47e71dfa8b6f2282f68765b88d2171a23b902",
      "yellow-mask.png" => "042b8434a6482980f087efb39ff8cc8296ecbef0b5e9caf79196975856da2940",
      "white-mask.png" => "97e02e2bdcda125da1c78257492f3ceb0145ba5b39f5c60d5df43fce3567bf50"
    }
  end
  let(:three_mf_digests) do
    {
      "3D/3dmodel.model" => "826f0a1c68f0851514ca512f1dcabe2b36174f1d956bf132e312aa2f81a8fdce",
      "Metadata/layer_config_ranges.xml" => "563ecd308a1769189a76e42f02f3632b93d932929b43f01f0343bd7bf520b885",
      "Metadata/model_settings.config" => "89b7fb93e180379f3a845e2a957b2308d2f5a144bf2178b2fca2f41bf65413d6",
      "Metadata/project_settings.config" => "623dd63f4dad5b8e496b0404257260c0b42d5097e633c8a921df84fae1da555c",
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
      corrected = Vips::Image.new_from_file(File.join(result.path, "corrected-input.png"))
      expect([corrected.width, corrected.height]).to eq([5, 5])
      expect(Digest::SHA256.hexdigest(corrected.write_to_memory))
        .to eq("30112800eb0c764234fbe90adec3456023df308fb0f231ba3add7ceb8fff19aa")
      expect(normalized_json_digest(result.path, "settings.json", "input_path"))
        .to eq("545eb15d4ec1a20a972677bba61a62679e58565a65fc807ec8b185d1b3cf1fc4")
      expect(normalized_json_digest(result.path, "manifest.json", "job_id"))
        .to eq("3baee682ddd829402b3d6452666c7cc09bbe7438e892d28587cf67624aad3058")
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

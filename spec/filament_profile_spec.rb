# frozen_string_literal: true

RSpec.describe Lithop::FilamentProfile do
  it "uses the Bambu Lab PLA CMYK Lithophane bundle by default" do
    profile = described_class.default

    expect(profile.id).to eq("bambu_lab_pla_basic_cmyw")
    expect(profile.product_url).to eq("https://jp.store.bambulab.com/products/pla-cmyk-lithophane")
    expect(profile.reference_url).to eq(
      "https://wiki.bambulab.com/en/knowledge-sharing/CMYK-color-lithophane-printing-instructions"
    )
    expect(profile.materials.map(&:channel)).to eq(%i[cyan magenta yellow white])
    expect(profile.materials.map(&:name)).to eq(
      ["PLA Basic Cyan", "PLA Basic Magenta", "PLA Basic Yellow", "PLA Basic White"]
    )
    expect(profile.materials.map(&:color_code)).to eq(%w[10603 10202 10400 10100])
    expect(profile.materials.map(&:display_color)).to eq(%w[#0086D6FF #EC008CFF #FCE300FF #FFFFFFFF])
    expect(profile.materials.map(&:diameter_mm)).to all(eq(1.75))
    expect(described_class.validate!(profile)).to be(true)
  end

  it "maps exact material display colors to pure CMY channels" do
    expect(described_class.display_cmy([0, 134, 214].map { |value| value.fdiv(255) })).to eq([1.0, 0.0, 0.0])
    expect(described_class.display_cmy([236, 0, 140].map { |value| value.fdiv(255) })).to eq([0.0, 1.0, 0.0])
    expect(described_class.display_cmy([252, 227, 0].map { |value| value.fdiv(255) })).to eq([0.0, 0.0, 1.0])
    expect(described_class.display_cmy([1.0, 0.0, 0.0])).to be_nil
  end

  it "maps material display-color mixtures to their labeled CMY proportions" do
    mappings = {
      [16, 24, 32] => [0.2, 0.4, 0.4],
      [118, 0, 129] => [0.4, 0.6, 0.0],
      [0, 0, 117] => [0.4, 0.6, 0.0],
      [0, 67, 166] => [0.6, 0.4, 0.0],
      [0, 127, 107] => [0.6, 0.0, 0.4],
      [0, 119, 0] => [0.4, 0.0, 0.6],
      [126, 173, 0] => [0.4, 0.0, 0.6],
      [243, 114, 0] => [0.0, 0.4, 0.6],
      [233, 0, 0] => [0.0, 0.4, 0.6],
      [235, 0, 70] => [0.0, 0.6, 0.4]
    }

    mappings.each do |rgb, expected_cmy|
      expect(described_class.display_cmy(rgb.map { |value| value.fdiv(255) })).to eq(expected_cmy)
    end
  end

  it "keeps chart composition fixed while opacity controls density" do
    cyan_50_percent = [127, 194, 234].map { |value| value.fdiv(255) }
    cyan_magenta_50_percent = [186, 127, 192].map { |value| value.fdiv(255) }

    cyan = described_class.display_sample(cyan_50_percent)
    cyan_magenta = described_class.display_sample(cyan_magenta_50_percent)

    expect(cyan.cmy).to eq([1.0, 0.0, 0.0])
    expect(cyan.density).to be_within(0.01).of(0.5)
    expect(cyan_magenta.cmy).to eq([0.4, 0.6, 0.0])
    expect(cyan_magenta.density).to be_within(0.01).of(0.5)
  end

  it "maps the chart CMY black while preserving its opacity as density" do
    black_50_percent = [135, 139, 143].map { |value| value.fdiv(255) }
    sample = described_class.display_sample(black_50_percent)

    expect(sample.cmy).to eq([0.2, 0.4, 0.4])
    expect(sample.density).to be_within(0.01).of(0.5)
  end
end

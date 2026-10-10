# frozen_string_literal: true

require "rexml/document"
require "rexml/xpath"

RSpec.describe Lithop::Calibration::TargetSVG do
  let(:settings) { Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0) }
  let(:target) { Lithop::Calibration::Target.new(settings:) }

  it "writes an editable 140 by 104 mm SVG matching the calibration layout" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "calibration.svg")
      described_class.write(path, target)
      document = REXML::Document.new(File.read(path))

      expect(document.root.attributes["width"]).to eq("140mm")
      expect(document.root.attributes["height"]).to eq("104mm")
      expect(document.root.attributes["viewBox"]).to eq("0 0 140 104")
      expect(REXML::XPath.match(document, "//*[contains(@class, 'patch')]").length).to eq(144)
      expect(REXML::XPath.first(document, "//*[@id='R000']")).not_to be_nil
      expect(REXML::XPath.first(document, "//*[@id='R119']")).not_to be_nil
      expect(REXML::XPath.first(document, "//*[@id='W07']")).not_to be_nil
    end
  end
end

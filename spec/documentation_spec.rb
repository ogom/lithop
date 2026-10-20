# frozen_string_literal: true

require "stringio"
require "vips"

# Helpers for validating human-facing Markdown navigation.
module DocumentationHelpers
  ROOT = Pathname(__dir__).join("..").expand_path
  DOCUMENTS = [ROOT.join("README.md"), *ROOT.glob("docs/*.md"), *ROOT.glob("doc/*.md")].freeze

  module_function

  def local_links
    DOCUMENTS.flat_map do |source|
      source.read.scan(/\[[^\]]+\]\(([^)]+)\)/).flatten.filter_map do |destination|
        next if destination.match?(/\A(?:https?:|mailto:)/)

        [source, destination]
      end
    end
  end

  def resolve(source, destination)
    relative_path, fragment = destination.split("#", 2)
    target = relative_path.empty? ? source : source.dirname.join(relative_path).cleanpath
    [target, fragment]
  end

  def heading_slugs(path)
    path.readlines(chomp: true).filter_map do |line|
      next unless line.match?(/\A#+\s+/)

      heading = line.sub(/\A#+\s+/, "").delete("`*_").downcase
      heading.gsub(/[^\p{L}\p{N}\s-]/, "").strip.gsub(/\s+/, "-")
    end
  end

  def heading_hierarchy_issues
    DOCUMENTS.filter_map do |path|
      levels = path.readlines.filter_map { |line| line[/\A(#+)\s+/, 1]&.length }
      invalid_jump = levels.each_cons(2).find { |parent, child| child > parent + 1 }
      next if levels.first == 1 && invalid_jump.nil?

      path.relative_path_from(ROOT).to_s
    end
  end

  def section(path, heading)
    lines = path.readlines(chomp: true)
    start = lines.index("## #{heading}")
    raise "missing documentation section: #{heading}" unless start

    lines[(start + 1)..].take_while { |line| !line.start_with?("## ") }.join("\n")
  end

  def long_options(text)
    text.scan(/--[a-z][a-z-]*/).uniq.sort
  end

  def table_first_column(path, heading)
    section(path, heading).scan(/^\| `([^`]+)` \|/).flatten
  end

  def parser_options(command)
    long_options(Lithop::CLIOptions.public_send(command, {}, StringIO.new).to_s)
  end
end

RSpec.describe "Human-facing documentation" do
  it "keeps relative links and heading anchors valid" do
    failures = DocumentationHelpers.local_links.filter_map do |source, destination|
      target, fragment = DocumentationHelpers.resolve(source, destination)
      next "#{source.relative_path_from(DocumentationHelpers::ROOT)}: #{destination}" unless target.exist?
      next if fragment.nil? || DocumentationHelpers.heading_slugs(target).include?(fragment.downcase)

      "#{source.relative_path_from(DocumentationHelpers::ROOT)}: #{destination}"
    end

    expect(failures).to be_empty, "broken documentation links:\n#{failures.join("\n")}"
  end

  it "keeps the reader path in the documentation index" do
    index = DocumentationHelpers::ROOT.join("docs/README.md").read
    expected = %w[
      getting-started.md bambu-studio.md troubleshooting.md artifacts.md
      config.md command.md color-model.md calibration.md local-ui.md
    ]

    expect(expected).to all(satisfy { |target| index.include?("](#{target})") })
  end

  it "keeps one top-level heading and a valid heading hierarchy" do
    expect(DocumentationHelpers.heading_hierarchy_issues).to be_empty
  end

  it "preserves printing safety and the current layer design" do
    workflow = DocumentationHelpers::ROOT.join("docs/bambu-studio.md").read
    layer_model = DocumentationHelpers::ROOT.join("docs/color-model.md").read

    expect(workflow).to include("7層の`Cyan -> Magenta -> Yellow -> White`")
    expect(workflow).to include("印刷を開始しないでください")
    expect(layer_model).to include("## 現行の積層構造")
    expect(layer_model).to include("Cyan -> Magenta -> Yellow")
    expect(layer_model).to include("7層の`Cyan -> Magenta -> Yellow -> White`")
  end

  it "describes cell-based previews without claiming colorimetric prediction" do
    guide = DocumentationHelpers::ROOT.join("docs/getting-started.md").read
    calibration = DocumentationHelpers::ROOT.join("docs/calibration.md").read

    expect(guide).to include("`transmission.png`")
    expect(guide).to include("`cyan-mask.png`など")
    expect(guide).to include("測色予測ではありません")
    expect(guide).to include("左上がモデルの`+Y`側")
    expect(calibration).to include("上段左の`R000`")
    expect(calibration).to include("下段の`W00`から`W07`")
  end

  it "documents every long option shown by each command parser" do
    command = DocumentationHelpers::ROOT.join("docs/command.md")
    sections = {
      generation: "画像からリトファンを生成する",
      calibration: "校正片を生成する",
      ui: "ローカルUIを起動する",
      clean: "生成物を削除する"
    }

    sections.each do |parser, heading|
      documented = DocumentationHelpers.long_options(DocumentationHelpers.section(command, heading))
      expect(documented).to eq(DocumentationHelpers.parser_options(parser)), heading
    end
  end

  it "keeps the input settings table synchronized with the accepted keys" do
    config = DocumentationHelpers::ROOT.join("docs/config.md")
    documented = DocumentationHelpers.table_first_column(config, "生成設定")

    expect(documented).to match_array(Lithop::Settings::DEFAULTS.keys.map(&:to_s))
    expect(Lithop::SettingsFile::ALLOWED_KEYS).to match_array(documented + ["schema_version"])
    expect(config.read).to include("`schema_version`")
  end

  it "keeps documented artifact names synchronized with small generated jobs" do
    artifacts = DocumentationHelpers::ROOT.join("docs/artifacts.md")
    clock = instance_double("Clock", now: Time.utc(2026, 10, 8))
    normal_random = instance_double("Random", hex: "11111111")
    calibration_random = instance_double("Random", hex: "22222222")
    settings = Lithop::Settings.new(width: 2.0, height: 2.0, pixel_size: 1.0)

    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      normal = Lithop::Export.new(
        settings:, project_dir: directory, clock:, random: normal_random
      ).call(input)
      calibration = Lithop::Calibration::Export.new(
        settings:, project_dir: directory, clock:, random: calibration_random
      ).call

      normal_files = DocumentationHelpers.table_first_column(artifacts, "通常ジョブのファイル")
      expect(normal_files - ["calibration-profile.json"]).to match_array(normal.files)
      calibration_files = DocumentationHelpers.table_first_column(artifacts, "校正ジョブのファイル")
      expect(calibration_files).to match_array(calibration.files)
    end
  end

  it "keeps private references and unverified release claims out of distributed documents" do
    public_documents = [
      DocumentationHelpers::ROOT.join("README.md"),
      *DocumentationHelpers::ROOT.glob("docs/*.md")
    ]
    private_references = public_documents.filter_map do |path|
      contents = path.read
      forbidden = %r{(?:/Users/[^\s`)]+|\b20\d{6}T\d{6}Z-[0-9a-f]{8}\b|released gem|公開済み)}i
      next unless contents.match?(forbidden)

      path.relative_path_from(DocumentationHelpers::ROOT).to_s
    end

    expect(private_references).to be_empty
  end

  it "identifies the product as a local CMYW color lithophane generator" do
    readme = DocumentationHelpers::ROOT.join("README.md").read
    index = DocumentationHelpers::ROOT.join("docs/README.md").read
    getting_started = DocumentationHelpers::ROOT.join("docs/getting-started.md").read
    gemspec = DocumentationHelpers::ROOT.join("lithop.gemspec").read

    expect(readme).to include("CMYW color lithophane generator", "without uploading")
    expect(index).to include("カラーLithophane（リトファン）", "画像を外部へ送信せず")
    expect(getting_started).to include("カラーLithophane（リトファン）")
    expect(gemspec).to include("CMYW lithophane", "locally", "JPEG, PNG, and SVG")
  end
end

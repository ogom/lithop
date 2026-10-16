# frozen_string_literal: true

require "json"
require "vips"

RSpec.describe Lithop::CLI do
  def run_cli(arguments, cwd:)
    out = StringIO.new
    err = StringIO.new
    status = described_class.run(arguments, out:, err:, cwd:)
    [status, out.string, err.string]
  end

  it "removes only the build directory in the current project" do
    Dir.mktmpdir do |directory|
      build_dir = File.join(directory, "build")
      source = File.join(directory, "source.png")
      FileUtils.mkdir_p(File.join(build_dir, "job"))
      File.write(File.join(build_dir, "job", "output.3mf"), "data")
      File.write(source, "keep")

      status, output, error = run_cli(["clean"], cwd: directory)

      expect(status).to eq(0)
      expect(output).to include("Removed #{build_dir}")
      expect(error).to be_empty
      expect(Dir).not_to exist(build_dir)
      expect(File).to exist(source)
    end
  end

  it "uses the explicit project directory and succeeds when build is absent" do
    Dir.mktmpdir do |directory|
      project = File.join(directory, "project")
      FileUtils.mkdir_p(project)

      status, output, = run_cli(["clean", "--project-dir", project], cwd: directory)

      expect(status).to eq(0)
      expect(output).to include("No build directory: #{File.join(project, "build")}")
    end
  end

  it "refuses to follow a build symbolic link" do
    Dir.mktmpdir do |directory|
      target = File.join(directory, "artifacts")
      FileUtils.mkdir_p(target)
      File.symlink(target, File.join(directory, "build"))

      status, _output, error = run_cli(["clean"], cwd: directory)

      expect(status).to eq(1)
      expect(error).to include("refusing to remove a symbolic link")
      expect(Dir).to exist(target)
    end
  end

  it "uses lithop in usage and error messages" do
    status, _output, error = run_cli([], cwd: Dir.pwd)

    expect(status).to eq(1)
    expect(error).to start_with("Usage: lithop IMAGE [options]")
  end

  it "shows current defaults and excludes retired generation option names" do
    out = StringIO.new

    expect { described_class.run(["--help"], out:, err: StringIO.new, cwd: Dir.pwd) }
      .to raise_error(SystemExit) { |error| expect(error.status).to eq(0) }
    expect(out.string).to include("default: cmy")
    expect(out.string).to include("Model width (default: 140.0)")
    expect(out.string).to include("Model height (default: 104.0)")
    expect(out.string).to include("0.2/0.4 (default: 0.2)")
    expect(out.string).to include("Layer height after first layer (default: 0.1)")
    expect(out.string).to include("CMY/W color layers: 4/5/7 (default: 7)")
    expect(out.string).to include("--tile-count COUNT")
    expect(out.string).to include("--separate-z-parts")
    expect(out.string).to include("--color-region-parts COUNT")
    expect(out.string).to include("--brightness PERCENT")
    expect(out.string).to include("--contrast PERCENT")
    expect(out.string).to include("--saturation PERCENT")
    expect(out.string).not_to include("--resolution")
    expect(out.string).not_to include("--nozzle MM")
    expect(out.string).not_to include("--first-layer MM")
    expect(out.string).not_to include("--color-match")
  end

  it "loads project settings and lets command-line options override them" do
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, "config"))
      File.write(
        File.join(directory, "config", "settings.json"),
        JSON.generate(
          schema_version: 1,
          width: 3.0,
          height: 2.0,
          pixel_size: 1.0,
          nozzle_diameter: 0.4,
          margin_left: 1.0,
          brightness: -10.0,
          contrast: 15.0,
          saturation: -20.0
        )
      )
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)

      status, output, error = run_cli(
        [
          input, "--nozzle-diameter", "0.2", "--margin-right", "1",
          "--image-fit", "contain", "--crop-position-x", "0.25", "--crop-position-y", "0.75",
          "--crop-scale", "0.8", "--color-pixel-size", "1.5",
          "--brightness", "20", "--contrast", "25", "--saturation", "30",
          "--separate-z-parts", "--color-region-parts", "2"
        ],
        cwd: directory
      )

      expect(status).to eq(0)
      expect(error).to be_empty
      expect(output).to match(/Estimated \d+ STL and \d+ CMYW 3MF triangles before writing/)
      expect(output).to include("CMYW by material:")
      job = Dir[File.join(directory, "build", "*")].fetch(0)
      settings = JSON.parse(File.read(File.join(job, "settings.json")))
      expect(settings.fetch("width")).to eq(3.0)
      expect(settings.fetch("pixel_size")).to eq(1.0)
      expect(settings.fetch("nozzle_diameter")).to eq(0.2)
      expect(settings.fetch("margin_left")).to eq(1.0)
      expect(settings.fetch("margin_right")).to eq(1.0)
      expect(settings.fetch("image_fit")).to eq("contain")
      expect(settings.fetch("crop_position_x")).to eq(0.25)
      expect(settings.fetch("crop_position_y")).to eq(0.75)
      expect(settings.fetch("crop_scale")).to eq(0.8)
      expect(settings.fetch("color_pixel_size")).to eq(1.5)
      expect(settings.values_at("brightness", "contrast", "saturation")).to eq([20.0, 25.0, 30.0])
      expect(settings.fetch("effective_color_pixel_size")).to eq(1.5)
      expect(settings.fetch("separate_z_parts")).to be(true)
      expect(settings.fetch("color_region_parts")).to eq(2)
      expect(settings.fetch("input_settings_path")).to eq(File.join(directory, "config", "settings.json"))
    end
  end

  it "generates a complete job from SVG input" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.svg")
      File.write(
        input,
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 2">' \
        '<rect width="2" height="2" fill="#0086D6"/></svg>'
      )

      status, output, error = run_cli(
        [input, "--width", "2", "--height", "2", "--pixel-size", "1"], cwd: directory
      )

      expect(status).to eq(0)
      expect(error).to be_empty
      expect(output).to include("Generated")
      job = Dir[File.join(directory, "build", "*")].fetch(0)
      expect(File).to exist(File.join(job, "lithop.3mf"))
      expect(File).to exist(File.join(job, "cmyk_white.stl"))
      expect(File).to exist(File.join(job, "preview.png"))
    end
  end

  it "reports a missing explicitly selected settings file" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      File.write(input, "not read")

      status, _output, error = run_cli([input, "--config", "missing.json"], cwd: directory)

      expect(status).to eq(1)
      expect(error).to include("settings file does not exist")
    end
  end

  it "reports output filesystem errors without a backtrace" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      project = File.join(directory, "not-a-directory")
      Vips::Image.black(2, 2).pngsave(input)
      File.write(project, "occupied")

      status, _output, error = run_cli(
        [input, "--width", "2", "--height", "2", "--pixel-size", "1", "--project-dir", project],
        cwd: directory
      )

      expect(status).to eq(1)
      expect(error).to start_with("lithop: ")
      expect(error).not_to include("lib/lithop")
    end
  end

  it "generates a calibration target and a draft profile" do
    Dir.mktmpdir do |directory|
      status, output, error = run_cli(["calibrate"], cwd: directory)

      expect(status).to eq(0)
      expect(error).to be_empty
      expect(output).to include("Generated 128 calibration patches")
      job = Dir[File.join(directory, "build", "*-calibration")].fetch(0)
      expect(File).to exist(File.join(job, "calibration.3mf"))
      expect(File).to exist(File.join(job, "calibration.svg"))
      profile = JSON.parse(File.read(File.join(job, "calibration-profile.json")))
      manifest = JSON.parse(File.read(File.join(job, "manifest.json")))
      expect(profile.fetch("patches").length).to eq(128)
      expect(manifest.fetch("recipe_patch_count")).to eq(120)
      expect(manifest.fetch("white_thickness_patch_count")).to eq(8)
      expect(manifest.fetch("layout")).to include("width_mm" => 140.0, "height_mm" => 104.0)
    end
  end

  it "loads an explicitly selected settings file" do
    Dir.mktmpdir do |directory|
      preset = File.join(directory, "fine.json")
      File.write(preset, JSON.generate(width: 3.0, height: 2.0, pixel_size: 1.0))
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)

      status, _output, error = run_cli([input, "--config", "fine.json"], cwd: directory)

      expect(status).to eq(0)
      expect(error).to be_empty
      job = Dir[File.join(directory, "build", "*")].fetch(0)
      settings = JSON.parse(File.read(File.join(job, "settings.json")))
      expect(settings.fetch("width")).to eq(3.0)
      expect(settings.fetch("input_settings_path")).to eq(preset)
    end
  end

  it "selects a complete measured calibration profile" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      settings = Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0)
      profile_path = File.join(directory, "measured.json")
      measured_calibration_profile(settings, profile_id: "cli-measured").write(profile_path)

      status, _output, error = run_cli(
        [input, "--width", "1", "--height", "1", "--pixel-size", "1", "--calibration-profile", profile_path],
        cwd: directory
      )

      expect(status).to eq(0)
      expect(error).to be_empty
      job = Dir[File.join(directory, "build", "*")].fetch(0)
      manifest = JSON.parse(File.read(File.join(job, "manifest.json")))
      expect(manifest.dig("color_model", "calibration", "profile_id")).to eq("cli-measured")
    end
  end

  it "rejects an incomplete calibration profile before creating a job" do
    Dir.mktmpdir do |directory|
      input = File.join(directory, "input.png")
      Vips::Image.black(2, 2).pngsave(input)
      settings = Lithop::Settings.new(width: 1.0, height: 1.0, pixel_size: 1.0)
      target = Lithop::Calibration::Target.new(settings:)
      profile_path = File.join(directory, "draft.json")
      Lithop::Calibration::Profile.template(profile_id: "draft", settings:, target:).write(profile_path)

      status, _output, error = run_cli(
        [input, "--width", "1", "--height", "1", "--pixel-size", "1", "--calibration-profile", profile_path],
        cwd: directory
      )

      expect(status).to eq(1)
      expect(error).to include("calibration profile is incomplete")
      expect(Dir).not_to exist(File.join(directory, "build"))
    end
  end
end

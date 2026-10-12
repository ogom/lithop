# frozen_string_literal: true

require "optparse"
require "fileutils"

module Lithop
  # Command-line interface for generating and cleaning lithophane projects.
  class CLI
    include CLICalibration

    def self.run(argv, out: $stdout, err: $stderr, cwd: Dir.pwd)
      new(out:, err:, cwd:).run(argv)
    end

    def initialize(out:, err:, cwd:)
      @out = out
      @err = err
      @cwd = File.expand_path(cwd)
    end

    def run(argv)
      return clean(argv.drop(1)) if argv.first == "clean"
      return calibrate(argv.drop(1)) if argv.first == "calibrate"

      options = {}
      parser = CLIOptions.generation(options, @out)
      arguments = parser.parse(argv)
      if arguments.length != 1
        @err.puts parser
        return 1
      end

      input = File.expand_path(arguments.first, @cwd)
      raise InputError, "input file does not exist: #{input}" unless File.file?(input)

      calibration_profile_path = options.delete(:calibration_profile)
      project_dir, settings, settings_path = load_settings(options)
      calibration_profile, calibration_profile_path = load_calibration_profile(calibration_profile_path, settings)
      if calibration_profile
        calibration = Export::CalibrationInput.new(profile: calibration_profile, path: calibration_profile_path)
      end
      result = Export.new(
        settings:,
        project_dir:,
        input_settings_path: settings_path,
        calibration:,
        progress: method(:report_estimate)
      ).call(input)
      @out.puts "Generated #{result.triangle_count} STL and #{result.three_mf_triangle_count} CMYW 3MF triangles"
      @out.puts "in #{result.path}"
      result.files.each { |file| @out.puts "  #{file}" }
      0
    rescue OptionParser::ParseError, Error, SystemCallError => e
      @err.puts "lithop: #{e.message}"
      1
    end

    private

    def report_estimate(estimate)
      @out.puts(
        "Estimated #{estimate.stl_triangle_count} STL and " \
        "#{estimate.three_mf_triangle_count} CMYW 3MF triangles before writing"
      )
      counts = estimate.triangle_counts_by_material.map { |material, count| "#{material}=#{count}" }.join(", ")
      @out.puts "  CMYW by material: #{counts}"
    end

    def load_settings(options, keys: nil)
      resolved = CLISettings.new(cwd: @cwd).call(options, keys:)
      [resolved.project_dir, resolved.settings, resolved.input_settings_path]
    end

    def clean(argv)
      options = {}
      parser = CLIOptions.clean(options, @out)
      arguments = parser.parse(argv)
      raise OptionParser::InvalidArgument, arguments.join(" ") unless arguments.empty?

      project_dir = File.expand_path(options.fetch(:project_dir, @cwd), @cwd)
      validate_clean_target!(project_dir)
      build_dir = File.join(project_dir, "build")
      return report_missing_build(build_dir) unless File.exist?(build_dir) || File.symlink?(build_dir)

      raise Error, "refusing to remove a symbolic link: #{build_dir}" if File.symlink?(build_dir)
      raise Error, "build path is not a directory: #{build_dir}" unless File.directory?(build_dir)

      FileUtils.rm_r(build_dir)
      @out.puts "Removed #{build_dir}"
      0
    rescue OptionParser::ParseError, Error, SystemCallError => e
      @err.puts "lithop: #{e.message}"
      1
    end

    def validate_clean_target!(project_dir)
      raise Error, "refusing to clean the filesystem root" if project_dir == File::SEPARATOR
    end

    def report_missing_build(build_dir) = 0.tap { @out.puts "No build directory: #{build_dir}" }
  end
end

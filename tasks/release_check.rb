# frozen_string_literal: true

require "bundler"
require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"
require "tmpdir"
require_relative "../lib/lithop/version"

module Lithop
  # Runs the checks required before publishing a Lithop gem release.
  # rubocop:disable-next Metrics/ModuleLength
  module ReleaseCheck
    EXPECTED_FILES = (
      %w[
        CHANGELOG.md
        Cargo.lock
        Cargo.toml
        docs/images/cmyw-lithophane-preview.png
        ext/lithop_native/Cargo.toml
        ext/lithop_native/build.rs
        ext/lithop_native/extconf.rb
        ext/lithop_native/src/lib.rs
        LICENSE
        README.md
        RELEASING.md
        bin/lithop
        lib/lithop.rb
        lib/lithop/cli/image_options.rb
        lib/lithop/cli/settings.rb
        lib/lithop/export/generation.rb
        lib/lithop/export/previews.rb
        lib/lithop/formats/three_mf/part_writer.rb
        lib/lithop/instrumentation.rb
        lib/lithop/image/placement.rb
        lib/lithop/job_directory.rb
        lib/lithop/layer_structure.rb
        lib/lithop/native.rb
        lib/lithop/sampling_grid.rb
        lib/lithop/version.rb
        lib/lithop/web/app.rb
        lib/lithop/web/public/app.css
        lib/lithop/web/public/app.js
        lib/lithop/web/server.rb
        lib/lithop/web/settings_library.rb
        lib/lithop/web/views/index.erb
        sig/lithop.rbs
      ] + Dir["docs/*.md"]
    ).freeze

    module_function

    def call
      gem_file = File.expand_path("lithop-#{Lithop::VERSION}.gem")
      validate_package(gem_file)
      smoke_test(gem_file)
      puts "release check passed: #{File.basename(gem_file)}"
    end

    def validate_package(gem_file)
      package = Gem::Package.new(gem_file)
      specification = package.spec
      validate_name(specification)
      validate_version(specification)
      validate_changelog
      validate_contents(package)
      validate_metadata(specification)
      validate_dependencies(specification)
    end

    def validate_name(specification)
      abort "built gem name is not lithop" unless specification.name == "lithop"
    end

    def validate_version(specification)
      return if specification.version.to_s == Lithop::VERSION

      abort "built gem version does not match #{Lithop::VERSION}"
    end

    def validate_changelog
      entry = /^## #{Regexp.escape(Lithop::VERSION)} - \d{4}-\d{2}-\d{2}$/
      abort "CHANGELOG.md has no entry for #{Lithop::VERSION}" unless File.read("CHANGELOG.md").match?(entry)
    end

    def validate_contents(package)
      missing_files = EXPECTED_FILES - package.contents
      abort "built gem is missing: #{missing_files.join(", ")}" unless missing_files.empty?
    end

    def validate_metadata(specification)
      abort "built gem license is not MIT" unless specification.license == "MIT"
      abort "built gem does not require MFA" unless specification.metadata["rubygems_mfa_required"] == "true"
      abort "built gem has no changelog URI" unless specification.metadata["changelog_uri"]
      abort "built gem does not expose the lithop executable" unless specification.executables.include?("lithop")
    end

    def validate_dependencies(specification)
      %w[puma rackup rb_sys ruby-vips rubyzip sinatra].each do |name|
        dependency = specification.runtime_dependencies.find { |candidate| candidate.name == name }
        abort "built gem does not depend on #{name}" unless dependency
      end
    end

    def smoke_test(gem_file)
      Dir.mktmpdir("lithop-release-") do |directory|
        gem_home = File.join(directory, "gems")
        bin_dir = File.join(directory, "bin")
        FileUtils.mkdir_p([gem_home, bin_dir])
        gem_path = ([gem_home] + Gem.path).uniq.join(File::PATH_SEPARATOR)
        environment = { "GEM_HOME" => gem_home, "GEM_PATH" => gem_path }

        install_gem(environment, gem_home, bin_dir, gem_file)
        run_cli(environment, bin_dir)
        run_native_extension(environment)
        run_ui(environment, directory)
      end
    end

    def install_gem(environment, gem_home, bin_dir, gem_file)
      command = [
        RbConfig.ruby, "-S", "gem", "install", "--local", "--no-document", "--ignore-dependencies",
        "--install-dir", gem_home, "--bindir", bin_dir, gem_file
      ]
      run!(environment, command, "isolated gem install")
    end

    def run_cli(environment, bin_dir)
      stdout = run!(environment, [File.join(bin_dir, "lithop"), "--version"], "installed CLI")
      abort "installed CLI reported #{stdout.strip.inspect}" unless stdout.strip == Lithop::VERSION
    end

    def run_native_extension(environment)
      code = 'require "lithop"; abort "Rust extension unavailable" unless Lithop::Native.available?'
      run!(environment, [RbConfig.ruby, "-e", code], "installed Rust extension")
    end

    def run_ui(environment, project_dir)
      code = <<~RUBY
        require "lithop"
        require "lithop/web/app"
        app = Lithop::Web::App.configured(project_dir: ENV.fetch("LITHOP_SMOKE_PROJECT"), csrf_token: "smoke")
        response = Rack::MockRequest.new(app).get("/", "HTTP_HOST" => "127.0.0.1")
        abort "installed UI did not render bundled assets" unless response.status == 200 && response.body.include?("/app.css")
      RUBY
      ui_environment = environment.merge("LITHOP_SMOKE_PROJECT" => project_dir)
      run!(ui_environment, [RbConfig.ruby, "-e", code], "installed local UI")
    end

    def run!(environment, command, description)
      stdout, stderr, status = Bundler.with_unbundled_env do
        Open3.capture3(environment, *command)
      end
      abort "#{description} failed:\n#{stdout}#{stderr}" unless status.success?

      stdout
    end
  end
end

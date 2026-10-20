# frozen_string_literal: true

require_relative "lib/lithop/version"

packaged_files = Dir[
  "CHANGELOG.md", "LICENSE", "README.md", "RELEASING.md", "bin/lithop",
  "Cargo.lock", "Cargo.toml", "docs/**/*", "ext/**/*", "lib/**/*.rb",
  "lib/lithop/web/**/*.{erb,css,js}", "sig/**/*.rbs"
]

Gem::Specification.new do |spec|
  spec.name = "lithop"
  spec.version = Lithop::VERSION
  spec.authors = ["ogom"]
  spec.email = ["ogom@users.noreply.github.com"]

  spec.summary = "Create CMYW lithophane models locally from images."
  spec.description = "Lithop converts JPEG, PNG, and SVG images locally into STL and multipart CMYW 3MF models " \
                     "for backlit lithophane printing."
  spec.homepage = "https://github.com/ogom/lithop"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0.0"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = packaged_files
  spec.bindir = "bin"
  spec.executables = ["lithop"]
  spec.require_paths = ["lib"]
  spec.extensions = ["ext/lithop_native/extconf.rb"]

  spec.add_dependency "puma", "~> 7.0"
  spec.add_dependency "rackup", "~> 2.2"
  spec.add_dependency "rb_sys", "~> 0.9.128"
  spec.add_dependency "rexml", "~> 3.4"
  spec.add_dependency "ruby-vips", "~> 2.3"
  spec.add_dependency "rubyzip", "~> 3.7"
  spec.add_dependency "sinatra", "~> 4.2"
end

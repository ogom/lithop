# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new do |task|
  task.options = ["--cache-root", File.expand_path("tmp/rubocop_cache", __dir__)]
end

require "rb_sys/extensiontask"

gemspec = Gem::Specification.load("lithop.gemspec")
RbSys::ExtensionTask.new("lithop_native", gemspec) do |extension|
  extension.lib_dir = "lib/lithop_native"
end

task build: :compile
task spec: :compile

desc "Run Rust extension tests"
task :rust_spec do
  sh "cargo test --manifest-path ext/lithop_native/Cargo.toml"
end

Dir.glob("tasks/**/*.rake").each { |task_file| load task_file }

task default: %i[rust_spec spec rubocop]

# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new do |task|
  task.options = ["--cache-root", File.expand_path("tmp/rubocop_cache", __dir__)]
end

Dir.glob("tasks/**/*.rake").each { |task_file| load task_file }

task default: %i[spec rubocop]

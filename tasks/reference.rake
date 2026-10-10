# frozen_string_literal: true

require "json"
require_relative "../lib/lithop"
require_relative "../lib/lithop/reference_three_mf"

namespace :reference do
  desc "Inspect a reference 3MF without copying its source data: rake reference:inspect[PATH]"
  task :inspect, [:path] do |_task, arguments|
    path = arguments.fetch(:path) do
      raise ArgumentError, "usage: bundle exec rake 'reference:inspect[path/to/reference.3mf]'"
    end
    puts JSON.pretty_generate(Lithop::ReferenceThreeMF.new(path).call)
  end
end

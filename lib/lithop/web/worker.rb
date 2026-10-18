# frozen_string_literal: true

require "json"
require "lithop"

module Lithop
  module Web
    # Runs one UI conversion in a separate Ruby process.
    module Worker
      module_function

      def run(arguments, out: $stdout, err: $stderr)
        job_id, input_path, settings_path, project_dir = arguments
        raise Error, "invalid web worker arguments" unless arguments.length == 4

        loaded = SettingsFile.load(settings_path, required: true)
        settings = Settings.new(**loaded.values)
        result = Export.new(settings:, project_dir:, job_id:).call(input_path)
        out.puts "Generated #{result.three_mf_triangle_count} CMYW 3MF triangles in #{result.path}"
        0
      rescue Error, SystemCallError, JSON::ParserError => e
        err.puts "lithop: #{e.message}"
        1
      end
    end
  end
end

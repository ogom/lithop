# frozen_string_literal: true

require "puma"
require_relative "app"

module Lithop
  module Web
    # Starts the local UI with Puma on the loopback interface.
    module Server
      HOST = "127.0.0.1"
      DEFAULT_PORT = 4567

      module_function

      def run(project_dir:, port: DEFAULT_PORT)
        application = App.configured(project_dir:)
        application.run!(bind: HOST, port:, server: :puma)
      end
    end
  end
end

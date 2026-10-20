# frozen_string_literal: true

require "rbconfig"

module Lithop
  # Loads optional acceleration implemented by the bundled Rust extension.
  module Native
    class << self
      def available? = @available == true

      def enabled? = available? && ENV["LITHOP_DISABLE_NATIVE"] != "1"

      def backend = enabled? ? :rust : :ruby

      def loaded_extension_version
        extension_version if available? && respond_to?(:extension_version)
      end

      def diagnostics
        {
          backend:,
          available: available?,
          enabled: enabled?,
          extension_version: loaded_extension_version,
          lithop_version: Lithop::VERSION,
          ruby: RUBY_DESCRIPTION,
          platform: RbConfig::CONFIG.fetch("host")
        }
      end
    end
  end
end

begin
  require "lithop_native/lithop_native"
  Lithop::Native.instance_variable_set(:@available, true)
rescue LoadError
  Lithop::Native.instance_variable_set(:@available, false)
end

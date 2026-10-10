# frozen_string_literal: true

require "tmpdir"
require "lithop"
require_relative "support/calibration_profile_helpers"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.order = :random
  config.include CalibrationProfileHelpers
  Kernel.srand config.seed
end

# frozen_string_literal: true

module Lithop
  # Measures named generation stages for an optional benchmark listener.
  class Instrumentation
    def initialize(listener = nil)
      @listener = listener
    end

    def measure(stage)
      return yield unless @listener

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      if @listener && started
        elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
        @listener.call(stage, elapsed)
      end
    end
  end
end

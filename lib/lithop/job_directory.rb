# frozen_string_literal: true

require "fileutils"

module Lithop
  # Owns one temporary job directory and publishes it with an atomic rename.
  class JobDirectory
    attr_reader :destination, :temporary

    def initialize(project_dir:, job_id:)
      build_dir = File.join(File.expand_path(project_dir), "build")
      @destination = File.join(build_dir, job_id)
      @temporary = File.join(build_dir, ".tmp-#{job_id}")
      @owned = false
    end

    def call
      acquire
      result = yield temporary
      publish
      [destination, result]
    rescue StandardError, Interrupt
      cleanup
      raise
    end

    private

    def acquire
      FileUtils.mkdir_p(File.dirname(temporary))
      raise Error, "output already exists: #{destination}" if File.exist?(destination)

      Dir.mkdir(temporary)
      @owned = true
    rescue Errno::EEXIST
      raise Error, "output already exists: #{File.exist?(destination) ? destination : temporary}"
    end

    def publish
      raise Error, "output already exists: #{destination}" if File.exist?(destination)

      File.rename(temporary, destination)
      @owned = false
    end

    def cleanup
      return unless @owned

      FileUtils.rm_rf(temporary)
      @owned = false
    rescue StandardError
      @owned = false
    end
  end
end

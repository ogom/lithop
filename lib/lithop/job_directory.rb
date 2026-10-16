# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Lithop
  # Owns one temporary job directory and publishes it with an atomic rename.
  class JobDirectory
    OWNER_FILE = ".lithop-owner.json"
    Recovered = Data.define(:job_id, :path)

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

    def self.recover(project_dir:)
      build_dir = File.join(File.expand_path(project_dir), "build")
      Dir.glob(File.join(build_dir, ".tmp-*")).filter_map do |path|
        recover_directory(path)
      end
    end

    def self.recover_directory(path)
      return if File.symlink?(path) || !File.directory?(path)

      owner = JSON.parse(File.read(File.join(path, OWNER_FILE)))
      job_id = owner.fetch("job_id")
      return unless File.basename(path) == ".tmp-#{job_id}"
      return if process_alive?(Integer(owner.fetch("pid")))

      FileUtils.rm_rf(path)
      Recovered.new(job_id:, path:)
    rescue JSON::ParserError, KeyError, ArgumentError, SystemCallError
      nil
    end

    def self.process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
    private_class_method :recover_directory, :process_alive?

    private

    def acquire
      FileUtils.mkdir_p(File.dirname(temporary))
      raise Error, "output already exists: #{destination}" if File.exist?(destination)

      Dir.mkdir(temporary)
      @owned = true
      File.write(
        File.join(temporary, OWNER_FILE),
        JSON.generate(job_id: File.basename(destination), pid: Process.pid, created_at: Time.now.utc.iso8601(6))
      )
    rescue Errno::EEXIST
      raise Error, "output already exists: #{File.exist?(destination) ? destination : temporary}"
    end

    def publish
      raise Error, "output already exists: #{destination}" if File.exist?(destination)

      FileUtils.rm_f(File.join(temporary, OWNER_FILE))
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

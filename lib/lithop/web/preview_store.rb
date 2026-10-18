# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"

module Lithop
  module Web
    # Owns short-lived input files used for pre-conversion browser previews.
    class PreviewStore
      DIRECTORY = ".previews"
      MAXIMUM_AGE = 24 * 60 * 60
      ID_PATTERN = /\A[0-9a-f]{32}\z/

      def initialize(project_dir:, random: SecureRandom, clock: Time)
        @root = File.join(File.expand_path(project_dir), "build", DIRECTORY)
        @random = random
        @clock = clock
        @mutex = Mutex.new
        recover
      end

      def stage(upload:, filename:)
        extension = validate_extension(filename)
        @mutex.synchronize do
          validate_root!
          preview_id = unique_id
          directory = File.join(@root, preview_id)
          Dir.mkdir(directory, 0o700)
          input_path = File.join(directory, "input#{extension}")
          upload.rewind if upload.respond_to?(:rewind)
          File.open(input_path, "wb", 0o600) { |file| IO.copy_stream(upload, file) }
          File.write(
            File.join(directory, "preview.json"),
            JSON.generate(id: preview_id, filename: File.basename(filename.to_s), created_at: timestamp) << "\n"
          )
          preview_id
        rescue StandardError
          FileUtils.rm_r(directory) if defined?(directory) && File.directory?(directory) && !File.symlink?(directory)
          raise
        end
      end

      def with_input(preview_id)
        @mutex.synchronize do
          directory = directory_for(preview_id)
          raise InputError, "preview input not found" unless safe_directory?(directory)

          metadata = JSON.parse(File.read(File.join(directory, "preview.json")))
          extension = validate_extension(metadata.fetch("filename"))
          input_path = File.join(directory, "input#{extension}")
          raise InputError, "preview input not found" if File.symlink?(input_path) || !File.file?(input_path)

          yield input_path, metadata.fetch("filename")
        end
      rescue JSON::ParserError, KeyError, SystemCallError
        raise InputError, "preview input not found"
      end

      def discard(preview_id)
        @mutex.synchronize do
          directory = directory_for(preview_id)
          return false unless safe_directory?(directory)

          FileUtils.rm_r(directory)
          true
        end
      end

      private

      def validate_root!
        build_dir = File.dirname(@root)
        raise Error, "refusing to use a symbolic build directory" if File.symlink?(build_dir)
        raise Error, "refusing to use a symbolic preview directory" if File.symlink?(@root)

        FileUtils.mkdir_p(@root)
      end

      def validate_extension(filename)
        extension = File.extname(filename.to_s).downcase
        return extension if JobLauncher::ALLOWED_EXTENSIONS.include?(extension)

        raise InputError, "image must be a JPEG, PNG, or SVG file"
      end

      def directory_for(preview_id)
        raise InputError, "invalid preview ID" unless preview_id.to_s.match?(ID_PATTERN)

        File.join(@root, preview_id)
      end

      def safe_directory?(directory)
        File.directory?(directory) && !File.symlink?(directory) && File.dirname(directory) == @root
      end

      def unique_id
        10.times do
          candidate = @random.hex(16)
          return candidate if candidate.match?(ID_PATTERN) && !File.exist?(File.join(@root, candidate))
        end
        raise Error, "could not allocate preview input"
      end

      def recover
        return unless File.directory?(@root) && !File.symlink?(@root)

        cutoff = @clock.now - MAXIMUM_AGE
        Dir.children(@root).each do |name|
          next unless name.match?(ID_PATTERN)

          directory = File.join(@root, name)
          next unless safe_directory?(directory)
          next unless File.mtime(directory) < cutoff

          FileUtils.rm_r(directory)
        end
      rescue SystemCallError
        nil
      end

      def timestamp = @clock.now.utc.iso8601(6)
    end
  end
end

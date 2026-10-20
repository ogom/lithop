# frozen_string_literal: true

require "timeout"

module Lithop
  module Web
    # Hands a validated 3MF artifact to Bambu Studio through macOS LaunchServices.
    class BambuStudioLauncher
      BUNDLE_ID = "com.bambulab.bambu-studio"
      OPEN_COMMAND = "/usr/bin/open"
      DEFAULT_TIMEOUT_SECONDS = 5

      class LauncherError < StandardError; end
      class BusyError < LauncherError; end
      class UnsupportedPlatformError < LauncherError; end
      class UnavailableError < LauncherError; end
      class LaunchTimeoutError < LauncherError; end
      class InvalidArtifactError < LauncherError; end

      def initialize(platform: RUBY_PLATFORM, runner: nil, timeout_seconds: DEFAULT_TIMEOUT_SECONDS)
        @platform = platform
        @runner = runner || method(:run_command)
        @timeout_seconds = timeout_seconds
        @mutex = Mutex.new
        @active_jobs = Set.new
      end

      def open(job_id:, path:)
        begin_open(job_id)
        acquired = true
        validate!(path)
        command = [OPEN_COMMAND, "-b", BUNDLE_ID, path]
        raise UnavailableError, "Bambu Studio could not be opened" unless @runner.call(command, @timeout_seconds)

        true
      ensure
        finish_open(job_id) if acquired
      end

      def active?(job_id) = @mutex.synchronize { @active_jobs.include?(job_id) }
      def supported? = @platform.include?("darwin")

      private

      def begin_open(job_id)
        @mutex.synchronize do
          raise BusyError, "Bambu Studio launch is already in progress" unless @active_jobs.empty?

          @active_jobs.add(job_id)
        end
      end

      def finish_open(job_id) = @mutex.synchronize { @active_jobs.delete(job_id) }

      def validate!(path)
        raise UnsupportedPlatformError, "opening Bambu Studio is supported on macOS" unless supported?
        raise InvalidArtifactError, "artifact must be a 3MF file" unless File.extname(path).casecmp?(".3mf")
        raise InvalidArtifactError, "3MF artifact not found" unless File.file?(path)
      end

      def run_command(command, timeout_seconds)
        pid = Process.spawn(*command, out: File::NULL, err: File::NULL)
        Timeout.timeout(timeout_seconds) { Process.wait2(pid).last.success? }
      rescue Timeout::Error
        terminate(pid)
        raise LaunchTimeoutError, "Bambu Studio launch request timed out"
      rescue SystemCallError
        raise UnavailableError, "Bambu Studio could not be opened"
      end

      def terminate(pid)
        Process.kill("TERM", pid)
        Timeout.timeout(0.25) { Process.wait(pid) }
      rescue Timeout::Error
        Process.kill("KILL", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end
    end
  end
end

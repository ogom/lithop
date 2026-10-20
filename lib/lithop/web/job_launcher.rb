# frozen_string_literal: true

require "fileutils"
require "json"
require "rbconfig"
require "securerandom"
require "time"

module Lithop
  module Web
    # Stages an upload and starts the shared conversion engine in a child process.
    # rubocop:disable-next Metrics/ClassLength
    class JobLauncher
      ALLOWED_EXTENSIONS = %w[.jpeg .jpg .png .svg].freeze
      WORK_DIRECTORY = ".web"

      # rubocop:disable-next Metrics/ParameterLists
      def initialize(
        project_dir:, random: SecureRandom, clock: Time, process: Process,
        sleeper: Kernel.method(:sleep), cancel_grace: 1.0, kill_grace: 1.0
      )
        @project_dir = File.expand_path(project_dir)
        @random = random
        @clock = clock
        @build_dir = File.join(@project_dir, "build")
        @work_root = File.join(@build_dir, WORK_DIRECTORY)
        @process = process
        @sleeper = sleeper
        @cancel_grace = cancel_grace
        @kill_grace = kill_grace
        @children = {}
        @children_mutex = Mutex.new
        recover
      end

      def start(upload:, filename:, settings:)
        validate_build_directory!
        extension = validate_extension(filename)
        job_id = "#{@clock.now.utc.strftime("%Y%m%dT%H%M%SZ")}-#{@random.hex(4)}"
        work_dir = File.join(@work_root, job_id)
        FileUtils.mkdir_p(work_dir)
        input_path = File.join(work_dir, "input#{extension}")
        settings_path = File.join(work_dir, "settings.json")
        copy_upload(upload, input_path)
        write_settings(settings, settings_path)
        write_request_record(job_id, filename, settings)
        pid = spawn_worker(job_id:, input_path:, settings_path:, work_dir:)
        @children_mutex.synchronize { @children[job_id] = pid }
        write_launch_record(work_dir, job_id, pid)
        reap(job_id, pid, work_dir)
        job_id
      rescue StandardError
        abort_spawn(job_id, pid) if defined?(pid) && pid
        FileUtils.rm_r(work_dir) if defined?(work_dir) && File.directory?(work_dir)
        FileUtils.rm_f(request_record_path(job_id)) if defined?(job_id) && job_id
        raise
      end

      def cancel(job_id)
        request_path = JobExecution.request_cancel(project_dir: @project_dir, job_id:)
        pid = owned_pid(job_id)
        escalate_cancellation(job_id, pid) if pid
        request_path
      end

      def active?(job_id) = !owned_pid(job_id).nil?

      private

      def validate_build_directory!
        raise Error, "refusing to use a symbolic build directory" if File.symlink?(@build_dir)
        raise Error, "refusing to use a symbolic UI work directory" if File.symlink?(@work_root)

        FileUtils.mkdir_p(@work_root)
      end

      def validate_extension(filename)
        extension = File.extname(filename.to_s).downcase
        return extension if ALLOWED_EXTENSIONS.include?(extension)

        raise InputError, "image must be a JPEG, PNG, or SVG file"
      end

      def copy_upload(upload, destination)
        upload.rewind if upload.respond_to?(:rewind)
        File.open(destination, "wb", 0o600) { |file| IO.copy_stream(upload, file) }
      end

      def write_settings(settings, path)
        values = settings.to_h.slice(*Settings::DEFAULTS.keys)
        File.write(path, JSON.pretty_generate({ schema_version: SettingsFile::SCHEMA_VERSION }.merge(values)) << "\n")
      end

      def write_request_record(job_id, filename, settings)
        FileUtils.mkdir_p(File.join(@build_dir, ".jobs"))
        values = settings.to_h.slice(*Settings::DEFAULTS.keys)
        File.write(
          request_record_path(job_id),
          JSON.generate(
            { input_name: File.basename(filename.to_s) }.merge(values)
          ) << "\n",
          mode: "w", perm: 0o600
        )
      end

      def request_record_path(job_id) = File.join(@build_dir, ".jobs", "#{job_id}.request.json")

      def spawn_worker(job_id:, input_path:, settings_path:, work_dir:)
        log_path = File.join(@build_dir, ".jobs", "#{job_id}.log")
        FileUtils.mkdir_p(File.dirname(log_path))
        @process.spawn(
          RbConfig.ruby, "-I", library_root, "-rlithop/web/worker", "-e",
          "exit Lithop::Web::Worker.run(ARGV)", job_id, input_path, settings_path, @project_dir,
          out: [log_path, "a"], err: %i[child out], pgroup: true, chdir: work_dir
        )
      end

      def write_launch_record(work_dir, job_id, pid)
        File.write(
          File.join(work_dir, "launch.json"),
          JSON.generate(job_id:, pid:, created_at: @clock.now.utc.iso8601(6)) << "\n"
        )
      end

      def reap(job_id, pid, work_dir)
        Thread.new do
          @process.wait(pid)
        rescue Errno::ECHILD
          nil
        ensure
          @children_mutex.synchronize { @children.delete(job_id) if @children[job_id] == pid }
          reconcile_exited_jobs([job_id])
          FileUtils.rm_r(work_dir) if File.directory?(work_dir)
        end
      end

      def abort_spawn(job_id, pid)
        @process.kill("KILL", -pid) if @process.getpgid(pid) == pid
        @process.wait(pid)
      rescue SystemCallError
        nil
      ensure
        @children_mutex.synchronize { @children.delete(job_id) if @children[job_id] == pid }
      end

      def escalate_cancellation(job_id, pid)
        Thread.new do
          @sleeper.call(@cancel_grace)
          terminate_owned(job_id, pid, "TERM")
          @sleeper.call(@kill_grace)
          terminate_owned(job_id, pid, "KILL")
        rescue SystemCallError
          nil
        end
      end

      def terminate_owned(job_id, pid, signal)
        return unless owned_pid(job_id) == pid
        return unless @process.getpgid(pid) == pid

        @process.kill(signal, -pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def owned_pid(job_id)
        @children_mutex.synchronize { @children[job_id] }
      end

      def recover
        stale_job_ids = if File.directory?(@work_root)
                          stale_work_directories
                        else
                          []
                        end
        reconcile_exited_jobs(stale_job_ids)
      rescue SystemCallError, JSON::ParserError
        nil
      end

      def stale_work_directories
        Dir.children(@work_root).filter_map do |name|
          next unless name.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]*\z/)

          directory = File.join(@work_root, name)
          next if File.symlink?(directory) || !File.directory?(directory)
          next if live_launch?(directory)

          FileUtils.rm_r(directory)
          name
        end
      end

      def reconcile_exited_jobs(job_ids)
        recovered_ids = JobDirectory.recover(project_dir: @project_dir).map(&:job_id)
        (job_ids + recovered_ids).uniq.each do |job_id|
          JobExecution.finalize_process_exit(project_dir: @project_dir, job_id:, clock: @clock)
        end
      end

      def live_launch?(directory)
        record = JSON.parse(File.read(File.join(directory, "launch.json")))
        @process.kill(0, Integer(record.fetch("pid")))
        true
      rescue Errno::ESRCH, Errno::ENOENT, KeyError, ArgumentError
        false
      rescue Errno::EPERM
        true
      end

      def library_root = File.expand_path("../..", __dir__)
    end
  end
end

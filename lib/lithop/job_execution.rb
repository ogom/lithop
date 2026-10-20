# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Lithop
  class JobCancelled < Error; end

  # Persists one conversion's state and limits a project to one active conversion.
  # rubocop:disable-next Metrics/ClassLength
  class JobExecution
    SCHEMA_VERSION = 1
    ACTIVE_STATES = %w[queued running cancelling].freeze
    FINAL_STATES = %w[completed failed cancelled].freeze
    Progress = Data.define(:job_id, :state, :phase, :percent, :message, :updated_at)

    attr_reader :job_id, :status_path

    def initialize(project_dir:, job_id:, progress: nil, clock: Time)
      validate_job_id!(job_id)
      @project_dir = File.expand_path(project_dir)
      @job_id = job_id
      @progress_callback = progress
      @clock = clock
      @build_dir = File.join(@project_dir, "build")
      @jobs_dir = File.join(@build_dir, ".jobs")
      @status_path = File.join(@jobs_dir, "#{job_id}.json")
      @cancel_path = File.join(@jobs_dir, "#{job_id}.cancel")
      @transition_lock_path = File.join(@jobs_dir, "#{job_id}.transition.lock")
      @lock_path = File.join(@build_dir, ".lithop.lock")
      @lock = nil
      @transition_lock = nil
      @record = base_record
    end

    def call
      prepare
      transition("queued", phase: "queued", percent: 0, message: "Waiting to start")
      acquire_lock
      recover_temporary_directories
      raise_if_cancelled!
      transition("running", phase: "starting", percent: 0, message: "Conversion started", started_at: timestamp)
      result = yield self
      raise_if_cancelled! unless @publication_committed
      complete(result)
      result
    rescue JobCancelled, Interrupt => e
      record_terminal_state(
        "cancelled", phase: "cancelled", message: "Conversion cancelled", error: e
      )
      raise
    rescue StandardError => e
      record_terminal_state("failed", phase: "failed", message: "Conversion failed", error: e)
      raise
    ensure
      release_lock
      release_transition_lock
      remove_cancel_request if prepared?
    end

    def progress(phase:, percent:, message:)
      raise_if_cancelled!
      transition("running", phase: phase.to_s, percent: normalize_percent(percent), message: message.to_s)
      raise_if_cancelled!
    end

    def checkpoint!
      @transition_mutex = self.class.send(:transition_mutex, @transition_lock_path)
      @transition_mutex.lock
      @transition_mutex_locked = true
      @transition_lock = File.open(@transition_lock_path, File::RDWR | File::CREAT, 0o600)
      @transition_lock.flock(File::LOCK_EX)
      raise_if_cancelled!
    rescue StandardError
      release_transition_lock
      raise
    end

    # Once JobDirectory has atomically published the output, late cancellation
    # must not turn a complete artifact set into a cancelled job.
    def publication_committed!(message: "Artifacts published")
      @publication_committed = true
      transition("running", phase: "publishing", percent: 99, message:)
    end

    def self.request_cancel(project_dir:, job_id:, clock: Time)
      validate_job_id!(job_id)
      jobs_dir = File.join(File.expand_path(project_dir), "build", ".jobs")
      FileUtils.mkdir_p(jobs_dir)
      status_path = File.join(jobs_dir, "#{job_id}.json")
      path = File.join(jobs_dir, "#{job_id}.cancel")
      lock_path = File.join(jobs_dir, "#{job_id}.transition.lock")
      requested_at = clock.now.utc.iso8601(6)
      requested = false
      transition_mutex(lock_path).synchronize do
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          unless final_status?(status_path)
            atomic_write(path, JSON.generate(job_id:, requested_at:))
            mark_cancelling(status_path, requested_at)
            requested = true
          end
        end
      end
      path if requested
    end

    def self.finalize_process_exit(project_dir:, job_id:, clock: Time)
      validate_job_id!(job_id)
      build_dir = File.join(File.expand_path(project_dir), "build")
      jobs_dir = File.join(build_dir, ".jobs")
      status_path = File.join(jobs_dir, "#{job_id}.json")
      cancel_path = File.join(jobs_dir, "#{job_id}.cancel")
      record = if File.file?(status_path)
                 JSON.parse(File.read(status_path))
               else
                 process_exit_record(job_id:, cancelled: File.file?(cancel_path), clock:)
               end
      return record unless ACTIVE_STATES.include?(record["state"])

      now = clock.now.utc.iso8601(6)
      output_path = File.join(build_dir, job_id)
      finalize_exit_record(record, output_path:, cancelled: File.file?(cancel_path), now:)
      atomic_write(status_path, JSON.pretty_generate(record) << "\n")
      record
    rescue JSON::ParserError, SystemCallError
      nil
    ensure
      FileUtils.rm_f(cancel_path) if defined?(cancel_path)
    end

    class << self
      private

      def finalize_exit_record(record, output_path:, cancelled:, now:)
        if File.directory?(output_path) && !File.symlink?(output_path)
          record.merge!(
            "state" => "completed", "phase" => "completed", "percent" => 100.0,
            "message" => "Conversion completed", "updated_at" => now, "finished_at" => now,
            "output_path" => output_path, "files" => artifact_files(output_path), "error" => nil
          )
        elsif record["state"] == "cancelling" || cancelled
          record.merge!(
            "state" => "cancelled", "phase" => "cancelled", "message" => "Conversion cancelled",
            "updated_at" => now, "finished_at" => now
          )
        else
          record.merge!(
            "state" => "failed", "phase" => "failed", "message" => "Conversion process exited",
            "updated_at" => now, "finished_at" => now,
            "error" => { "class" => "Lithop::Error", "message" => "conversion process exited before completion" }
          )
        end
      end

      def validate_job_id!(job_id)
        return if job_id.is_a?(String) && job_id.match?(/\A[0-9A-Za-z][0-9A-Za-z._-]*\z/)

        raise Error, "invalid job ID: #{job_id.inspect}"
      end

      def atomic_write(path, contents)
        temporary = "#{path}.tmp-#{Process.pid}-#{Thread.current.object_id}"
        File.write(temporary, contents)
        File.rename(temporary, path)
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary)
      end

      def mark_cancelling(path, requested_at)
        return unless File.file?(path)

        record = JSON.parse(File.read(path))
        return unless ACTIVE_STATES.include?(record["state"])

        record.merge!(
          "state" => "cancelling",
          "phase" => "cancelling",
          "message" => "Cancellation requested",
          "updated_at" => requested_at
        )
        atomic_write(path, JSON.pretty_generate(record) << "\n")
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def final_status?(path)
        File.file?(path) && FINAL_STATES.include?(JSON.parse(File.read(path))["state"])
      rescue JSON::ParserError, SystemCallError
        false
      end

      def transition_mutex(path)
        @transition_mutex_guard ||= Mutex.new
        @transition_mutex_guard.synchronize do
          @transition_mutexes ||= {}
          @transition_mutexes[path] ||= Mutex.new
        end
      end

      def artifact_files(output_path)
        Dir.glob("**/*", base: output_path).select do |name|
          path = File.join(output_path, name)
          File.file?(path) && !File.symlink?(path)
        end.sort
      end

      def process_exit_record(job_id:, cancelled:, clock:)
        now = clock.now.utc.iso8601(6)
        {
          "schema_version" => SCHEMA_VERSION, "job_id" => job_id,
          "state" => cancelled ? "cancelling" : "running",
          "phase" => cancelled ? "cancelling" : "starting", "percent" => 0,
          "message" => cancelled ? "Cancellation requested" : "Conversion process started",
          "created_at" => now, "updated_at" => now, "started_at" => nil,
          "finished_at" => nil, "output_path" => nil, "files" => nil, "error" => nil
        }
      end
    end

    private

    def validate_job_id!(value) = self.class.send(:validate_job_id!, value)

    def prepare
      FileUtils.mkdir_p(@jobs_dir)
      raise Error, "job state already exists: #{@status_path}" if File.exist?(@status_path)

      @prepared = true
    end

    def prepared? = @prepared

    def acquire_lock
      @lock = File.open(@lock_path, File::RDWR | File::CREAT, 0o600)
      return if @lock.flock(File::LOCK_EX | File::LOCK_NB)

      raise Error, "another conversion is already running in project: #{@project_dir}"
    end

    def release_lock
      return unless @lock

      @lock.flock(File::LOCK_UN)
      @lock.close
      @lock = nil
    rescue IOError, SystemCallError
      @lock = nil
    end

    def release_transition_lock
      if @transition_lock
        @transition_lock.flock(File::LOCK_UN)
        @transition_lock.close
        @transition_lock = nil
      end
      if @transition_mutex_locked
        @transition_mutex.unlock
        @transition_mutex_locked = false
      end
    rescue IOError, SystemCallError
      @transition_lock = nil
      if @transition_mutex_locked
        @transition_mutex.unlock
        @transition_mutex_locked = false
      end
    end

    def recover_temporary_directories
      JobDirectory.recover(project_dir: @project_dir).each do |recovered|
        mark_recovered_job(recovered)
      end
    end

    def mark_recovered_job(recovered)
      path = File.join(@jobs_dir, "#{recovered.job_id}.json")
      return unless File.file?(path)

      record = JSON.parse(File.read(path))
      return unless ACTIVE_STATES.include?(record["state"])

      now = timestamp
      record.merge!(
        "state" => "failed",
        "phase" => "recovered",
        "message" => "Abandoned temporary data recovered",
        "updated_at" => now,
        "finished_at" => now,
        "error" => { "class" => "Lithop::Error", "message" => "conversion process ended before completion" }
      )
      self.class.send(:atomic_write, path, JSON.pretty_generate(record) << "\n")
    rescue JSON::ParserError, SystemCallError
      nil
    end

    def complete(result)
      additions = { finished_at: timestamp }
      additions[:output_path] = result.path if result.respond_to?(:path)
      additions[:files] = result.files if result.respond_to?(:files)
      transition("completed", phase: "completed", percent: 100, message: "Conversion completed", **additions)
    end

    def transition(state, phase:, percent:, message:, **additions)
      now = timestamp
      @record.merge!(
        state:,
        phase:,
        percent: normalize_percent(percent),
        message:,
        updated_at: now,
        **additions
      )
      self.class.send(:atomic_write, @status_path, JSON.pretty_generate(@record) << "\n")
      notify
    end

    def notify
      return unless @progress_callback

      @progress_callback.call(
        Progress.new(
          job_id:,
          state: @record.fetch(:state),
          phase: @record.fetch(:phase),
          percent: @record.fetch(:percent),
          message: @record.fetch(:message),
          updated_at: @record.fetch(:updated_at)
        )
      )
    rescue StandardError
      nil
    end

    def record_terminal_state(state, phase:, message:, error:)
      return unless prepared?

      transition(state, phase:, percent: current_percent, message:, finished_at: timestamp,
                        error: error_record(error))
    rescue StandardError
      nil
    end

    def raise_if_cancelled!
      raise JobCancelled, "job #{job_id} was cancelled" if File.file?(@cancel_path)
    end

    def remove_cancel_request
      FileUtils.rm_f(@cancel_path) if @cancel_path
    rescue SystemCallError
      nil
    end

    def base_record
      now = timestamp
      {
        schema_version: SCHEMA_VERSION,
        job_id:,
        state: "queued",
        phase: "queued",
        percent: 0,
        message: "Waiting to start",
        created_at: now,
        updated_at: now,
        started_at: nil,
        finished_at: nil,
        output_path: nil,
        files: nil,
        error: nil
      }
    end

    def error_record(error) = { class: error.class.name, message: error.message }
    def timestamp = @clock.now.utc.iso8601(6)
    def current_percent = @record.fetch(:percent, 0)
    def normalize_percent(value) = Float(value).clamp(0.0, 100.0)
  end
end

# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "zip"

module Lithop
  module Web
    # Reads persisted job state and resolves only recorded output artifacts.
    # rubocop:disable-next Metrics/ClassLength
    class JobStore
      JOB_ID_PATTERN = /\A[0-9A-Za-z][0-9A-Za-z._-]*\z/
      INDEX_SCHEMA_VERSION = 1

      def initialize(project_dir:)
        @project_dir = File.expand_path(project_dir)
        @build_dir = File.join(@project_dir, "build")
        @jobs_dir = File.join(@build_dir, ".jobs")
        @work_root = File.join(@build_dir, JobLauncher::WORK_DIRECTORY)
        @archives_dir = File.join(@build_dir, ".downloads")
        @index_path = File.join(@jobs_dir, ".index.json")
        @index_mutex = Mutex.new
        @index = load_index
        recover_archives
      end

      def fetch(job_id)
        validate_job_id!(job_id)
        path = File.join(@jobs_dir, "#{job_id}.json")
        return merge_request_record(job_id, JSON.parse(File.read(path))) if File.file?(path)
        return merge_request_record(job_id, pending_record(job_id)) if File.directory?(File.join(@work_root, job_id))

        nil
      rescue JSON::ParserError, SystemCallError
        nil
      end

      def recent(limit: 12)
        entries = indexed_entries.sort_by { |entry| entry.fetch("job_id") }.reverse
        active, final = entries.partition { |entry| JobExecution::ACTIVE_STATES.include?(entry["state"]) }
        (active + final).first(limit).filter_map { |entry| fetch(entry.fetch("job_id")) }
      end

      def page(limit: 12, offset: 0, filters: {})
        records = indexed_entries
        term = filters[:query].to_s.strip.downcase
        records.select! { |record| searchable_text(record).include?(term) } unless term.empty?
        records.select! { |record| state_match?(record.fetch("state", ""), filters[:state]) }
        if present?(filters[:date_from])
          records.select! { |record| record["created_at"].to_s[0, 10] >= filters[:date_from] }
        end
        if present?(filters[:date_to])
          records.select! { |record| record["created_at"].to_s[0, 10] <= filters[:date_to] }
        end
        records = sort_records(records, filters[:sort])
        selected = records.slice(offset, limit) || []
        {
          "jobs" => selected.filter_map { |record| fetch(record.fetch("job_id")) }, "total" => records.length,
          "offset" => offset, "limit" => limit
        }
      end

      def archive_summary(job_id, scope:)
        names = archive_names(job_id, scope)
        files = names.map do |name|
          path = artifact(job_id, name)
          { "name" => name, "size_bytes" => File.size(path) }
        end
        { "scope" => scope, "files" => files, "file_count" => files.length,
          "size_bytes" => files.sum { |file| file.fetch("size_bytes") } }
      end

      def create_archive(job_id, scope:)
        summary = archive_summary(job_id, scope:)
        raise InputError, "no matching artifacts" if summary.fetch("files").empty?

        prepare_archives_directory!
        path = File.join(@archives_dir, "#{job_id}-#{scope}-#{SecureRandom.hex(8)}.zip")
        Zip::File.open(path, create: true) do |archive|
          summary.fetch("files").each do |file|
            name = file.fetch("name")
            archive.add(name, artifact(job_id, name))
          end
        end
        path
      rescue StandardError
        FileUtils.rm_f(path) if path
        raise
      end

      def artifact(job_id, name)
        record = fetch(job_id)
        raise InputError, "job not found" unless record
        raise InputError, "job is not complete" unless record["state"] == "completed"
        raise InputError, "artifact not found" unless record.fetch("files", []).include?(name)

        output = contained_realpath(record.fetch("output_path"), @build_dir)
        contained_realpath(File.join(output, name), output).tap do |path|
          raise InputError, "artifact not found" unless File.file?(path)
        end
      rescue KeyError
        raise InputError, "artifact not found"
      end

      def log(job_id)
        validate_job_id!(job_id)
        raise InputError, "job not found" unless fetch(job_id)

        path = File.join(@jobs_dir, "#{job_id}.log")
        raise InputError, "job log not found" unless File.file?(path) && !File.symlink?(path)

        contained_realpath(path, @jobs_dir)
      end

      def summary(job_id)
        record = fetch(job_id)
        raise InputError, "job not found" unless record

        output = expected_output(job_id)
        return { "file_count" => 0, "size_bytes" => 0 } unless safe_output?(output)

        files = regular_files(output)
        { "file_count" => files.length, "size_bytes" => files.sum { |path| File.size(path) } }
      rescue SystemCallError
        { "file_count" => 0, "size_bytes" => 0 }
      end

      def delete(job_id)
        validate_job_id!(job_id)
        FileUtils.mkdir_p(@jobs_dir)
        File.open(File.join(@jobs_dir, ".delete.lock"), File::RDWR | File::CREAT, 0o600) do |lock|
          raise Error, "another job deletion is in progress" unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          record = fetch(job_id)
          raise InputError, "job not found" unless record
          unless JobExecution::FINAL_STATES.include?(record["state"])
            raise InputError, "active jobs must be stopped before deletion"
          end

          output = expected_output(job_id)
          validate_recorded_output!(record, output)
          validate_work_directory!(job_id)
          removed = summary(job_id)
          remove_output(output)
          remove_work_directory(job_id)
          FileUtils.rm_f(File.join(@jobs_dir, "#{job_id}.log"))
          FileUtils.rm_f(File.join(@jobs_dir, "#{job_id}.cancel"))
          FileUtils.rm_f(File.join(@jobs_dir, "#{job_id}.transition.lock"))
          FileUtils.rm_f(File.join(@jobs_dir, "#{job_id}.request.json"))
          FileUtils.rm_f(File.join(@jobs_dir, "#{job_id}.json"))
          remove_index_entry(job_id)
          removed
        end
      end

      private

      def indexed_entries
        return [] unless File.directory?(@jobs_dir)

        @index_mutex.synchronize do
          names = Dir.glob("*.json", base: @jobs_dir).reject { |name| name.end_with?(".request.json") }
          job_ids = names.map { |name| File.basename(name, ".json") }
          existing = job_ids.to_h { |job_id| [job_id, true] }
          changed = @index.keys.any? { |job_id| !existing.key?(job_id) }
          @index.select! { |job_id, _entry| existing.key?(job_id) }
          job_ids.each do |job_id|
            entry = build_index_entry(job_id, @index[job_id])
            next unless entry
            next if entry == @index[job_id]

            @index[job_id] = entry
            changed = true
          end
          write_index if changed
          @index.values.map(&:dup)
        end
      end

      def build_index_entry(job_id, previous)
        status_path = File.join(@jobs_dir, "#{job_id}.json")
        request_path = File.join(@jobs_dir, "#{job_id}.request.json")
        signature = file_signature(status_path)
        request_signature = file_signature(request_path)
        if previous && previous["signature"] == signature && previous["request_signature"] == request_signature
          return previous
        end

        status = JSON.parse(File.read(status_path))
        request = request_signature ? JSON.parse(File.read(request_path)) : {}
        {
          "job_id" => job_id,
          "state" => status.fetch("state", ""),
          "created_at" => status["created_at"].to_s,
          "updated_at" => status["updated_at"].to_s,
          "input_name" => request["input_name"].to_s,
          "signature" => signature,
          "request_signature" => request_signature
        }
      rescue JSON::ParserError, SystemCallError
        previous
      end

      def file_signature(path)
        return unless File.file?(path) && !File.symlink?(path)

        stat = File.stat(path)
        [stat.size, stat.mtime.to_f]
      end

      def load_index
        return {} unless File.file?(@index_path) && !File.symlink?(@index_path)

        document = JSON.parse(File.read(@index_path))
        return {} unless document["schema_version"] == INDEX_SCHEMA_VERSION

        document.fetch("jobs", {}).select { |job_id, _entry| job_id.match?(JOB_ID_PATTERN) }
      rescue JSON::ParserError, KeyError, SystemCallError
        {}
      end

      def write_index
        temporary = "#{@index_path}.tmp-#{Process.pid}"
        File.write(
          temporary,
          JSON.generate("schema_version" => INDEX_SCHEMA_VERSION, "jobs" => @index) << "\n",
          mode: "w", perm: 0o600
        )
        File.rename(temporary, @index_path)
      ensure
        FileUtils.rm_f(temporary) if defined?(temporary)
      end

      def remove_index_entry(job_id)
        @index_mutex.synchronize do
          @index.delete(job_id)
          write_index if File.directory?(@jobs_dir)
        end
      end

      def searchable_text(record)
        [record["job_id"], record["input_name"]].compact.join(" ").downcase
      end

      def state_match?(value, filter)
        return true if filter.nil? || filter == "all"
        return JobExecution::ACTIVE_STATES.include?(value) if filter == "active"
        return %w[failed cancelled].include?(value) if filter == "failed"

        value == filter
      end

      def sort_records(records, sort)
        case sort
        when "created_asc" then records.sort_by { |record| [record["created_at"].to_s, record.fetch("job_id")] }
        when "name_asc" then records.sort_by { |record| [record["input_name"].to_s.downcase, record.fetch("job_id")] }
        when "name_desc"
          records.sort_by { |record| [record["input_name"].to_s.downcase, record.fetch("job_id")] }.reverse
        else
          active, final = records.partition { |record| JobExecution::ACTIVE_STATES.include?(record["state"]) }
          [active, final].flat_map do |group|
            group.sort_by { |record| [record["created_at"].to_s, record.fetch("job_id")] }.reverse
          end
        end
      end

      def archive_names(job_id, scope)
        record = fetch(job_id)
        raise InputError, "job not found" unless record
        raise InputError, "job is not complete" unless record["state"] == "completed"
        raise InputError, "archive scope is invalid" unless %w[models all].include?(scope)

        names = record.fetch("files", []) || []
        raise InputError, "artifact path is invalid" unless names.all? { |name| safe_archive_name?(name) }

        scope == "models" ? names.grep(/\.3mf\z/i) : names
      end

      def safe_archive_name?(name)
        value = name.to_s
        parts = value.split("/", -1)
        !value.empty? && !value.start_with?("/") && !value.include?("\\") &&
          parts.none? { |part| part.empty? || part == "." || part == ".." }
      end

      def recover_archives
        return unless File.directory?(@archives_dir) && !File.symlink?(@archives_dir)

        Dir.glob("*.zip", base: @archives_dir).each { |name| FileUtils.rm_f(File.join(@archives_dir, name)) }
      end

      def prepare_archives_directory!
        raise InputError, "archive directory must not be a symbolic link" if File.symlink?(@archives_dir)

        FileUtils.mkdir_p(@archives_dir, mode: 0o700)
        raise InputError, "archive path is not a directory" unless File.directory?(@archives_dir)
      end

      def present?(value) = !value.nil? && !value.to_s.empty?

      def validate_job_id!(job_id)
        raise InputError, "invalid job ID" unless job_id.to_s.match?(JOB_ID_PATTERN)
      end

      def contained_realpath(path, parent)
        resolved_parent = File.realpath(parent)
        resolved = File.realpath(path)
        prefix = "#{resolved_parent}#{File::SEPARATOR}"
        raise InputError, "artifact path leaves the build directory" unless resolved.start_with?(prefix)

        resolved
      rescue SystemCallError
        raise InputError, "artifact not found"
      end

      def expected_output(job_id) = File.join(@build_dir, job_id)

      def validate_recorded_output!(record, expected)
        recorded = record["output_path"]
        return if recorded.nil? || recorded.to_s.empty?
        return if File.expand_path(recorded) == expected

        raise InputError, "recorded output path does not match the job"
      end

      def safe_output?(path)
        File.directory?(path) && !File.symlink?(path) && File.dirname(path) == @build_dir
      end

      def regular_files(directory)
        Dir.glob("**/*", base: directory).filter_map do |name|
          path = File.join(directory, name)
          path if File.file?(path) && !File.symlink?(path)
        end
      end

      def remove_output(path)
        return unless File.exist?(path) || File.symlink?(path)
        raise InputError, "refusing to delete a symbolic job output" if File.symlink?(path)
        raise InputError, "job output is not a directory" unless File.directory?(path)

        FileUtils.rm_r(path)
      end

      def remove_work_directory(job_id)
        path = File.join(@work_root, job_id)
        return unless File.exist?(path) || File.symlink?(path)

        FileUtils.rm_r(path)
      end

      def validate_work_directory!(job_id)
        path = File.join(@work_root, job_id)
        return unless File.exist?(path) || File.symlink?(path)
        raise InputError, "refusing to delete a symbolic job work directory" if File.symlink?(path)
        raise InputError, "job work path is not a directory" unless File.directory?(path)
        raise InputError, "job process is still exiting" if live_work_process?(path)
      end

      def live_work_process?(path)
        launch = JSON.parse(File.read(File.join(path, "launch.json")))
        Process.kill(0, Integer(launch.fetch("pid")))
        true
      rescue Errno::ESRCH, Errno::ENOENT, KeyError, ArgumentError, JSON::ParserError
        false
      rescue Errno::EPERM
        true
      end

      def pending_record(job_id)
        {
          "job_id" => job_id, "state" => "queued", "phase" => "starting", "percent" => 0,
          "message" => "Starting conversion", "files" => nil
        }
      end

      def merge_request_record(job_id, record)
        path = File.join(@jobs_dir, "#{job_id}.request.json")
        return record unless File.file?(path)

        keys = ["input_name", *Settings::DEFAULTS.keys.map(&:to_s)]
        metadata = JSON.parse(File.read(path)).slice(*keys)
        record.merge(metadata)
      rescue JSON::ParserError, SystemCallError
        record
      end
    end
  end
end

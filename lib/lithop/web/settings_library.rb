# frozen_string_literal: true

require "fileutils"
require "json"
require "time"

module Lithop
  module Web
    # Persists reusable browser settings without changing config/settings.json.
    # rubocop:disable-next Metrics/ClassLength
    class SettingsLibrary
      SCHEMA_VERSION = 1
      PATH = File.join("config", "ui-settings.json")
      MAX_NAME_LENGTH = 80

      def initialize(project_dir:, clock: -> { Time.now.utc })
        @project_dir = File.expand_path(project_dir)
        @path = File.join(@project_dir, PATH)
        @clock = clock
      end

      def read
        document = load_document
        {
          "schema_version" => SCHEMA_VERSION,
          "presets" => document.fetch("presets").sort.to_h,
          "draft" => document["draft"]
        }
      end

      def save_preset(name, values)
        update do |document|
          document.fetch("presets")[validate_name!(name)] = entry(values)
        end
      end

      def rename_preset(name, new_name)
        update do |document|
          presets = document.fetch("presets")
          source = presets.delete(validate_name!(name))
          raise InputError, "preset not found" unless source

          target = validate_name!(new_name)
          raise InputError, "preset already exists" if presets.key?(target)

          presets[target] = source.merge("updated_at" => timestamp)
        end
      end

      def delete_preset(name)
        update do |document|
          removed = document.fetch("presets").delete(validate_name!(name))
          raise InputError, "preset not found" unless removed
        end
      end

      def save_draft(values)
        update { |document| document["draft"] = entry(values) }
      end

      def delete_draft
        update { |document| document.delete("draft") }
      end

      private

      def entry(values)
        { "settings" => normalize(values), "updated_at" => timestamp }
      end

      def normalize(values)
        supplied = values.to_h.slice(*SettingsForm::FIELD_NAMES).transform_values do |value|
          if value == true
            "1"
          elsif value == false
            ""
          elsif value.nil?
            nil
          else
            value.to_s
          end
        end
        resolved = SettingsForm.new(project_dir: @project_dir).resolve(supplied)
        SettingsForm.new(project_dir: @project_dir).values(resolved).slice(*SettingsForm::FIELD_NAMES)
      end

      def validate_name!(name)
        value = name.to_s.strip
        raise InputError, "preset name is required" if value.empty?
        raise InputError, "preset name is too long" if value.length > MAX_NAME_LENGTH
        raise InputError, "preset name contains unsupported characters" if value.match?(/[\x00-\x1f\x7f]/)

        value
      end

      def update
        FileUtils.mkdir_p(File.dirname(@path))
        lock_directory = File.join(@project_dir, "build")
        FileUtils.mkdir_p(lock_directory)
        lock_path = File.join(lock_directory, ".ui-settings.lock")
        File.open(lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
          lock.flock(File::LOCK_EX)
          document = load_document
          yield document
          write_document(document)
          read
        end
      end

      def load_document
        return empty_document unless File.file?(@path)
        raise InputError, "UI settings file must not be a symbolic link" if File.symlink?(@path)

        document = JSON.parse(File.read(@path))
        raise InputError, "unsupported UI settings schema" unless document["schema_version"] == SCHEMA_VERSION
        raise InputError, "invalid UI settings file" unless document["presets"].is_a?(Hash)

        validate_entries!(document)
        document
      rescue JSON::ParserError
        raise InputError, "invalid UI settings JSON"
      end

      def validate_entries!(document)
        document.fetch("presets").each_value { |value| validate_entry!(value) }
        validate_entry!(document["draft"]) if document["draft"]
      end

      def validate_entry!(entry)
        raise InputError, "invalid saved UI settings" unless entry.is_a?(Hash) && entry["settings"].is_a?(Hash)

        unknown = entry.fetch("settings").keys - SettingsForm::FIELD_NAMES
        raise InputError, "unsupported saved settings: #{unknown.join(", ")}" unless unknown.empty?

        entry["settings"] = normalize(entry.fetch("settings"))
      end

      def write_document(document)
        temporary = "#{@path}.tmp-#{Process.pid}"
        File.open(temporary, "w", 0o600) do |file|
          file.write(JSON.pretty_generate(document) << "\n")
          file.flush
          file.fsync
        end
        File.rename(temporary, @path)
      ensure
        FileUtils.rm_f(temporary) if temporary
      end

      def empty_document = { "schema_version" => SCHEMA_VERSION, "presets" => {} }
      def timestamp = @clock.call.iso8601(6)
    end
  end
end

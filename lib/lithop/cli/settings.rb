# frozen_string_literal: true

module Lithop
  # Resolves project paths and merges CLI, JSON, and default generation settings.
  class CLISettings
    Result = Data.define(:project_dir, :settings, :input_settings_path)

    def initialize(cwd:)
      @cwd = File.expand_path(cwd)
    end

    def call(options, keys: nil)
      values = options.dup
      project_dir = File.expand_path(values.delete(:project_dir) || @cwd, @cwd)
      explicit_settings_file = values.delete(:settings_file)
      input_settings_path = settings_path(project_dir, explicit_settings_file)
      file_settings = SettingsFile.load(input_settings_path, required: !explicit_settings_file.nil?)
      configured = keys ? file_settings.values.slice(*keys) : file_settings.values
      Result.new(
        project_dir:,
        settings: Settings.new(**configured, **values),
        input_settings_path: file_settings.path
      )
    end

    private

    def settings_path(project_dir, explicit_settings_file)
      return File.expand_path(explicit_settings_file, @cwd) if explicit_settings_file

      File.join(project_dir, SettingsFile::DEFAULT_PATH)
    end
  end
end

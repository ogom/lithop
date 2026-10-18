# frozen_string_literal: true

require "json"
require "fileutils"
require "rack/utils"
require "securerandom"
require "sinatra/base"
require_relative "settings_form"
require_relative "job_launcher"
require_relative "job_store"
require_relative "preview_store"
require_relative "settings_library"

module Lithop
  module Web
    # Local-only browser interface for conversion settings, progress, and artifacts.
    # rubocop:disable-next Metrics/ClassLength
    class App < Sinatra::Base
      ROOT = File.expand_path(__dir__)
      MAX_REQUEST_BYTES = 100 * 1024 * 1024

      # Streams an archive and removes the temporary file when Rack closes it.
      class TemporaryFileBody
        def initialize(path)
          @path = path
        end

        def each
          File.open(@path, "rb") do |file|
            yield file.read(64 * 1024) until file.eof?
          end
        ensure
          close
        end

        def close
          FileUtils.rm_f(@path) if @path
          @path = nil
        end
      end

      set :environment, :production
      set :logging, false
      set :show_exceptions, false
      set :raise_errors, false
      set :static, true
      set :public_folder, File.join(ROOT, "public")
      set :views, File.join(ROOT, "views")

      def self.configured(project_dir:, launcher: nil, preview_store: nil, csrf_token: SecureRandom.hex(32))
        Class.new(self).tap do |application|
          expanded = File.expand_path(project_dir)
          application.set :project_dir, expanded
          application.set :launcher, launcher || JobLauncher.new(project_dir: expanded)
          application.set :job_store, JobStore.new(project_dir: expanded)
          application.set :preview_store, preview_store || PreviewStore.new(project_dir: expanded)
          application.set :settings_library, SettingsLibrary.new(project_dir: expanded)
          application.set :csrf_token, csrf_token
        end
      end

      before do
        headers(
          "Cache-Control" => "no-store",
          "Content-Security-Policy" => "default-src 'self'; img-src 'self' blob: data:; " \
                                       "style-src 'self'; style-src-attr 'unsafe-inline'; script-src 'self'; " \
                                       "object-src 'none'; base-uri 'none'; " \
                                       "form-action 'self'; frame-ancestors 'none'",
          "Referrer-Policy" => "no-referrer",
          "X-Content-Type-Options" => "nosniff",
          "X-Frame-Options" => "DENY"
        )
        verify_request_size!
        verify_csrf! if request.post?
      end

      get "/" do
        prepare_page
        erb :index
      end

      post "/jobs" do
        form = SettingsForm.new(project_dir: settings.project_dir)
        resolved = form.resolve(params)
        job_id = start_job(resolved)
        if json_request?
          status 202
          content_type :json
          JSON.generate(job_id:, url: "/?job=#{Rack::Utils.escape_path(job_id)}")
        else
          redirect "/?job=#{job_id}", 303
        end
      rescue Error, SystemCallError => e
        discard_submitted_preview
        status 422
        @error = e.message
        prepare_page(submitted: params)
        erb :index
      end

      post "/api/previews" do
        upload = params["image"]
        raise InputError, "select a JPEG, PNG, or SVG image" unless valid_upload?(upload)

        preview_id = settings.preview_store.stage(
          upload: upload.fetch(:tempfile), filename: upload.fetch(:filename)
        )
        content_type :json
        JSON.generate(id: preview_id)
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/previews/:id/render" do
        resolved = SettingsForm.new(project_dir: settings.project_dir).resolve(params)
        png = settings.preview_store.with_input(params.fetch("id")) do |path, _filename|
          ImagePipeline.new(resolved).preview_png(path)
        end
        content_type "image/png"
        body png
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/previews/:id/discard" do
        discarded = settings.preview_store.discard(params.fetch("id"))
        content_type :json
        JSON.generate(ok: true, discarded:)
      rescue Error => e
        halt 422, json_error(e.message)
      end

      post "/api/tile-layout" do
        resolved = SettingsForm.new(project_dir: settings.project_dir).resolve(params)
        content_type "image/svg+xml"
        body TileLayoutSVG.document(settings: resolved, layout: TileLayout.new(resolved), background: false)
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-summary" do
        resolved = SettingsForm.new(project_dir: settings.project_dir).resolve(params)
        layout = TileLayout.new(resolved)
        content_type :json
        JSON.generate(
          tile_count: resolved.tile_count, tile_rows: layout.rows, tile_columns: layout.columns,
          z_plate_count: resolved.separate_z_parts ? resolved.color_region_parts + 1 : 1
        )
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      get "/api/settings-library" do
        content_type :json
        JSON.generate(settings.settings_library.read)
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-library/presets" do
        content_type :json
        JSON.generate(settings.settings_library.save_preset(params["name"], params))
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-library/presets/rename" do
        content_type :json
        JSON.generate(settings.settings_library.rename_preset(params["name"], params["new_name"]))
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-library/presets/delete" do
        content_type :json
        JSON.generate(settings.settings_library.delete_preset(params["name"]))
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-library/draft" do
        content_type :json
        JSON.generate(settings.settings_library.save_draft(params))
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      post "/api/settings-library/draft/delete" do
        content_type :json
        JSON.generate(settings.settings_library.delete_draft)
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      get "/api/jobs/:id" do
        record = settings.job_store.fetch(params.fetch("id"))
        halt 404, json_error("job not found") unless record

        content_type :json
        JSON.generate(present_job(record))
      end

      get "/api/jobs" do
        limit = Integer(params.fetch("limit", 12).to_s, 10).clamp(1, 50)
        offset = Integer(params.fetch("offset", 0).to_s, 10)
        halt 422, json_error("offset must be zero or greater") if offset.negative?
        content_type :json
        filters = {
          query: params["q"], state: params.fetch("state", "all"), date_from: params["date_from"],
          date_to: params["date_to"], sort: params.fetch("sort", "created_desc")
        }
        result = settings.job_store.page(limit:, offset:, filters:)
        result["jobs"] = result.fetch("jobs").map { |record| present_job(record) }
        JSON.generate(result)
      rescue ArgumentError
        halt 422, json_error("limit and offset must be integers")
      end

      get "/api/jobs/:id/archive-summary" do
        summary = settings.job_store.archive_summary(params.fetch("id"), scope: params.fetch("scope", "all"))
        job_id = Rack::Utils.escape_path(params.fetch("id"))
        scope = Rack::Utils.escape(params.fetch("scope", "all"))
        summary["download_url"] = "/jobs/#{job_id}/archive?scope=#{scope}"
        content_type :json
        JSON.generate(summary)
      rescue Error, SystemCallError => e
        halt 422, json_error(e.message)
      end

      get "/jobs/:id/archive" do
        path = nil
        job_id = params.fetch("id")
        scope = params.fetch("scope", "all")
        path = settings.job_store.create_archive(job_id, scope:)
        content_type "application/zip"
        attachment "#{job_id}-#{scope}.zip"
        headers "Content-Length" => File.size(path).to_s
        body TemporaryFileBody.new(path)
      rescue Error, SystemCallError, Zip::Error => e
        FileUtils.rm_f(path) if path
        halt 422, e.message
      end

      post "/api/jobs/delete" do
        job_ids = Array(params["job_ids"]).uniq
        halt 422, json_error("select at least one job") if job_ids.empty?
        deleted = []
        errors = []
        job_ids.each do |job_id|
          if launcher_active?(job_id)
            errors << { job_id:, error: "job process is still exiting" }
            next
          end
          removed = settings.job_store.delete(job_id)
          deleted << { job_id: }.merge(removed)
        rescue Error => e
          errors << { job_id:, error: e.message }
        end
        content_type :json
        JSON.generate(ok: errors.empty?, deleted:, errors:)
      end

      post "/jobs/:id/cancel" do
        job_id = params.fetch("id")
        record = settings.job_store.fetch(job_id)
        halt 404, json_error("job not found") unless record
        halt 422, json_error("job is not active") unless JobExecution::ACTIVE_STATES.include?(record["state"])

        settings.launcher.cancel(job_id)
        content_type :json
        JSON.generate(ok: true, job_id:)
      rescue Error => e
        halt 422, json_error(e.message)
      end

      post "/jobs/:id/delete" do
        job_id = params.fetch("id")
        halt 422, json_error("job process is still exiting") if launcher_active?(job_id)
        removed = settings.job_store.delete(job_id)
        content_type :json
        JSON.generate({ ok: true, job_id: }.merge(removed))
      rescue Error => e
        halt 422, json_error(e.message)
      end

      get "/jobs/:id/files/*" do
        path = settings.job_store.artifact(params.fetch("id"), params.fetch("splat").first)
        send_file(path, disposition: inline_artifact?(path) ? "inline" : "attachment")
      rescue Error => e
        halt 404, e.message
      end

      get "/jobs/:id/log" do
        send_file(settings.job_store.log(params.fetch("id")), type: "text/plain", disposition: "inline")
      rescue Error => e
        halt 404, e.message
      end

      not_found { "Not found" }

      error do
        content_type :json
        status 500
        json_error("local UI request failed")
      end

      helpers do
        def h(value) = Rack::Utils.escape_html(value.to_s)

        def checked?(key)
          @values.fetch(key.to_s, false) == true || @values.fetch(key.to_s, nil) == "1"
        end

        def selected?(key, value) = @values[key.to_s].to_s == value.to_s
      end

      private

      def prepare_page(submitted: nil)
        form = SettingsForm.new(project_dir: settings.project_dir)
        @values = form.values
        if submitted
          SettingsForm::FIELD_NAMES.each { |key| @values[key] = submitted[key] if submitted.key?(key) }
          @values["separate_z_parts"] = submitted["separate_z_parts"] == "1"
        end
        @jobs = settings.job_store.recent.map do |job|
          job.merge(settings.job_store.summary(job.fetch("job_id")))
        end
        prepare_navigation
        @csrf_token = settings.csrf_token
      rescue Error => e
        @error ||= e.message
        @values ||= Settings::DEFAULTS.transform_keys(&:to_s)
        @jobs ||= []
        @initial_view ||= "create"
        @project_name ||= File.basename(settings.project_dir)
        @csrf_token = settings.csrf_token
      end

      def prepare_navigation
        @selected_job_id = params["job"]
        requested_view = params["view"].to_s
        @initial_view = if %w[create jobs presets].include?(requested_view)
                          requested_view
                        elsif @selected_job_id
                          "jobs"
                        else
                          "create"
                        end
        @project_name = File.basename(settings.project_dir)
      end

      def valid_upload?(upload)
        upload.is_a?(Hash) && upload[:tempfile].respond_to?(:read) && !upload[:filename].to_s.empty?
      end

      def launcher_active?(job_id)
        settings.launcher.respond_to?(:active?) && settings.launcher.active?(job_id)
      end

      def start_job(resolved)
        preview_id = params["preview_id"].to_s
        return start_staged_job(preview_id, resolved) unless preview_id.empty?

        upload = params["image"]
        raise InputError, "select a JPEG, PNG, or SVG image" unless valid_upload?(upload)

        settings.launcher.start(
          upload: upload.fetch(:tempfile), filename: upload.fetch(:filename), settings: resolved
        )
      end

      def start_staged_job(preview_id, resolved)
        settings.preview_store.with_input(preview_id) do |path, filename|
          File.open(path, "rb") { |upload| settings.launcher.start(upload:, filename:, settings: resolved) }
        end
      ensure
        settings.preview_store.discard(preview_id)
      end

      def discard_submitted_preview
        preview_id = params["preview_id"].to_s
        settings.preview_store.discard(preview_id) unless preview_id.empty?
      rescue Error
        nil
      end

      def verify_request_size!
        length = request.content_length.to_i
        halt 413, "Upload is too large" if length > MAX_REQUEST_BYTES
      end

      def verify_csrf!
        supplied = params["csrf_token"].to_s
        supplied = request.env["HTTP_X_CSRF_TOKEN"].to_s if supplied.empty?
        expected = settings.csrf_token.to_s
        halt 403, "Invalid request token" unless secure_compare(supplied, expected)
      end

      def secure_compare(left, right)
        left.bytesize == right.bytesize && Rack::Utils.secure_compare(left, right)
      end

      def json_request?
        request.env.fetch("HTTP_ACCEPT", "").split(",").any? { |type| type.include?("application/json") }
      end

      def present_job(record)
        presented = record.dup
        files = record.fetch("files", []) || []
        presented["artifacts"] = files.map do |name|
          { "name" => name, "url" => artifact_url(record.fetch("job_id"), name) }
        end
        presented["preview_url"] = artifact_url(record.fetch("job_id"), "preview.png") if files.include?("preview.png")
        if files.include?("corrected-input.png")
          presented["corrected_input_url"] = artifact_url(record.fetch("job_id"), "corrected-input.png")
        end
        presented.merge!(manifest_presentation(record, files))
        presented["log_url"] = "/jobs/#{Rack::Utils.escape_path(record.fetch("job_id"))}/log" if job_log?(record)
        presented.merge!(settings.job_store.summary(record.fetch("job_id")))
        presented
      end

      def manifest_presentation(record, files)
        return {} unless record["state"] == "completed" && files.include?("manifest.json")

        manifest = JSON.parse(File.read(settings.job_store.artifact(record.fetch("job_id"), "manifest.json")))
        {
          "tile_layout_metadata" => manifest["tile_layout"],
          "tiles" => manifest["tiles"],
          "z_part_separation" => manifest.dig("color_model", "z_part_separation")
        }
      rescue Error, JSON::ParserError, SystemCallError
        {}
      end

      def job_log?(record)
        settings.job_store.log(record.fetch("job_id"))
        true
      rescue Error
        false
      end

      def artifact_url(job_id, name)
        encoded = name.split("/").map { |part| Rack::Utils.escape_path(part) }.join("/")
        "/jobs/#{Rack::Utils.escape_path(job_id)}/files/#{encoded}"
      end

      def inline_artifact?(path)
        %w[.png .svg .json .md .txt].include?(File.extname(path).downcase)
      end

      def json_error(message)
        content_type :json
        JSON.generate(error: message)
      end
    end
  end
end

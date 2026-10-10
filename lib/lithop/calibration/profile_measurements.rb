# frozen_string_literal: true

module Lithop
  module Calibration
    PatchMeasurement = Data.define(:patch_id, :recipe, :height, :transmitted_srgb, :luminance)

    # Exposes averaged measurements and completeness checks for a profile.
    module ProfileMeasurements
      def profile_id = data.fetch("profile_id")
      def status = data.fetch("status")

      def measurements(kind)
        data.fetch("patches").select { |patch| patch.fetch("kind") == kind.to_s }.map do |patch|
          samples = patch.fetch("measurements")
          PatchMeasurement.new(
            patch_id: patch.fetch("patch_id"),
            recipe: patch.fetch("recipe"),
            height: patch.fetch("total_thickness_mm"),
            transmitted_srgb: mean_rgb(samples),
            luminance: mean(samples.map { |sample| sample.fetch("luminance") })
          )
        end
      end

      def validate_complete!
        issues = []
        patches = data.fetch("patches")
        missing = missing_patch_ids(patches)
        issues << "missing measurements for #{missing.join(", ")}" if missing.any?
        issues << "recipe set does not match the active palette" unless complete_recipe_set?(patches)
        issues << "expected #{Target::WHITE_STAGE_COUNT} White thickness patches" unless complete_white_stages?(patches)
        issues << "white_point is missing" unless reference_present?("white_point")
        issues << "black_point is missing" unless reference_present?("black_point")
        return true if issues.empty?

        raise InputError, "calibration profile is incomplete: #{issues.join("; ")}"
      end

      private

      def missing_patch_ids(patches)
        patches.filter_map { |patch| patch.fetch("patch_id") if patch.fetch("measurements").empty? }
      end

      def complete_recipe_set?(patches)
        palette = Palette.new(
          layer_count: data.dig("structure", "color_layer_count"),
          pigment_order: data.dig("structure", "pigment_order").map(&:to_sym)
        )
        expected = palette.recipes.map { |recipe| recipe_key(recipe.to_h.fetch(:counts).transform_keys(&:to_s)) }
        actual = patches.filter_map do |patch|
          recipe_key(patch.fetch("recipe")) if patch.fetch("kind") == "recipe"
        end
        actual.length == expected.length && actual.uniq.sort == expected.sort
      end

      def complete_white_stages?(patches)
        stages = patches.select { |patch| patch.fetch("kind") == "white_thickness" }
        thicknesses = stages.map { |patch| patch.fetch("total_thickness_mm") }
        stages.length == Target::WHITE_STAGE_COUNT && thicknesses.uniq.length == stages.length
      end

      def reference_present?(key)
        reference = data.fetch("measurement").fetch(key)
        validate_measurement!(reference)
        true
      rescue InputError, KeyError
        false
      end

      def recipe_key(counts)
        Palette::MATERIALS.map { |material| counts.fetch(material.to_s) }.join(":")
      end

      def mean_rgb(samples)
        samples.map { |sample| sample.fetch("transmitted_srgb") }.transpose.map { |values| mean(values) }
      end

      def mean(values) = values.sum.fdiv(values.length)
    end
  end
end

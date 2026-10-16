# frozen_string_literal: true

module Lithop
  TileArtifact = Data.define(:tile, :name, :three_mf, :material_model)

  ExportArtifacts = Data.define(
    :stl_name,
    :tile_artifacts,
    :stl_triangle_count,
    :material_model,
    :tile_layout
  ) do
    def three_mf_names = tile_artifacts.map(&:name)

    def three_mf_name
      three_mf_names.fetch(0) if three_mf_names.one?
    end

    def three_mf
      results = tile_artifacts.map(&:three_mf)
      counts = results.each_with_object(Hash.new(0)) do |result, totals|
        result.triangle_counts_by_material.each { |material, count| totals[material] += count }
      end
      ThreeMF::Result.new(
        vertex_count: results.sum(&:vertex_count),
        triangle_count: results.sum(&:triangle_count),
        material_count: counts.length,
        object_count: results.sum(&:object_count),
        triangle_counts_by_material: counts.freeze
      )
    end
  end

  ExportResult = Data.define(
    :job_id,
    :path,
    :files,
    :triangle_count,
    :three_mf_triangle_count,
    :material_count,
    :object_count
  )
end

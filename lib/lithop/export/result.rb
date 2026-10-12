# frozen_string_literal: true

module Lithop
  ExportArtifacts = Data.define(
    :stl_name,
    :three_mf_name,
    :stl_triangle_count,
    :three_mf,
    :material_model
  )

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

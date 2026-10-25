# Changelog

## 0.4.0 - 2026-10-30

- Changes Z separation to 1–3 contiguous plates with a 0.10 mm first-layer Base White support on each; three-plate output uses eight 0.08 mm CMYW layers, equal source slices, a CMY-free third plate, and only one 0.08 mm Top White layer at the brightest thickness.
- Adds print color controls for all six CMY stacking orders with YMC as the default, optional Cyan or Magenta mixing into Yellow, and opt-in pale-color suppression.
- Moves Create, Jobs, and Presets into a GitHub-style top navigation, places the conversion action beside image selection, organizes settings into responsive panes, and adds bulk selection and deletion for recent jobs.
- Sets the standard maximum thickness to the printable 1.94 mm boundary with 0.01 mm UI increments and updates generated models, calibration stages, documentation, and artifact contracts accordingly.

## 0.3.0 - 2026-10-20

- Adds a loopback-only Sinatra/ERB/Puma UI with responsive Create, Jobs, and Presets panes, faster immediate JPEG/PNG/SVG input previews, reusable settings, drafts, and engine-rendered result views.
- Adds persistent job progress and cancellation, indexed searchable history, result comparison, ZIP downloads, safe bulk deletion, direct opening of completed 3MF artifacts in Bambu Studio on macOS, and bounded preview caching with browser timing diagnostics.
- Adds a Rust extension for CMY recipe selection, CMY mesh generation, 3MF vertex indexing, and XML output; the standard chart benchmark median improves from 36.800 seconds to 13.946 seconds while retaining the Ruby comparison path.
- Packages the UI and Rust sources in the source gem, adds `lithop doctor`, and verifies macOS/Ruby 4.0 builds, installed-gem native loading, Chromium/WebKit workflows, and Bambu Studio loading of unsplit and split 3MF outputs.

## 0.2.0 - 2026-10-16

- Adds exact-count CMYW 3MF tiling, plus optional four-plate output for three Base White-backed CMYW color regions and Top White.
- Aligns the CLI help and source-checkout settings with the 140 × 104 mm standard profile.
- Adds reproducible sRGB brightness, contrast, and saturation adjustments to JSON settings and the CLI.
- Records conversion progress and final status, supports cancellation and stale temporary-data recovery, and limits each project to one active conversion.

## 0.1.0 - 2026-10-12

- Converts JPEG, PNG, and validated self-contained SVG files up to 15 MB into a White reference STL and a single-plate multipart CMYW 3MF.
- Uses the standard 0.2 mm nozzle profile with two White base layers, seven `Cyan -> Magenta -> Yellow -> White` color layers, and a continuous upper White surface; four- and five-layer comparisons remain available.
- Maps material display colors and five-percent chart mixtures to labeled recipes, and generates matching 140 × 104 mm calibration SVG/3MF files with all 120 recipes and eight White thickness stages.
- Supports optional measured color and physical White-thickness calibration, JSON/CLI overrides, image placement, independent color cells, atomic output, Bambu metadata, previews, manifests, and safe cleanup; the 0.2 mm fine-line target is print-verified, while the current full chart and numerical color measurement remain pending.

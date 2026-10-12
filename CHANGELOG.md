# Changelog

## 0.1.0 - 2026-10-12

- Converts JPEG, PNG, and validated self-contained SVG files up to 15 MB into a White reference STL and a single-plate multipart CMYW 3MF.
- Uses the standard 0.2 mm nozzle profile with two White base layers, seven `Cyan -> Magenta -> Yellow -> White` color layers, and a continuous upper White surface; four- and five-layer comparisons remain available.
- Maps material display colors and five-percent chart mixtures to labeled recipes, and generates matching 140 × 104 mm calibration SVG/3MF files with all 120 recipes and eight White thickness stages.
- Supports optional measured color and physical White-thickness calibration, JSON/CLI overrides, image placement, independent color cells, atomic output, Bambu metadata, previews, manifests, and safe cleanup; the 0.2 mm fine-line target is print-verified, while the current full chart and numerical color measurement remain pending.

const workspace = document.querySelector(".workspace");
const form = document.querySelector("#conversion-form");
const fileInput = document.querySelector("#image-input");
const filePicker = document.querySelector("#file-picker");
const fileName = document.querySelector("#file-name");
const previewIdInput = document.querySelector("#preview-id");
const sourceImage = document.querySelector("#source-image");
const compareSourceImage = document.querySelector("#compare-source-image");
const sourcePlaceholder = document.querySelector("#source-placeholder");
const tileLayout = document.querySelector("#tile-layout");
const separateZParts = document.querySelector("#separate-z-parts");
const tileOverlay = document.querySelector("#tile-overlay");
const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
const stateLabels = {
  queued: "待機中", running: "変換中", cancelling: "停止要求中",
  completed: "完了", failed: "失敗", cancelled: "停止済み"
};
const previewKinds = [
  { name: "preview.png", label: "CMYW", description: "CMYW仕上がり" },
  { name: "cyan-mask.png", label: "Cyan", description: "Cyan材料マスク" },
  { name: "magenta-mask.png", label: "Magenta", description: "Magenta材料マスク" },
  { name: "yellow-mask.png", label: "Yellow", description: "Yellow材料マスク" },
  { name: "white-mask.png", label: "White", description: "White材料マスク" },
  { name: "transmission.png", label: "透過明度", description: "White厚みによる相対透過明度" },
  { name: "thickness.png", label: "厚み", description: "White厚みマップ" },
  { name: "tile-layout.svg", label: "タイル", description: "タイル配置" }
];
const previewLabels = Object.fromEntries(previewKinds.map(({ name, label }) => [name, label]));
const settingLabels = {
  width: "幅", height: "高さ", pixel_size: "XYセル", color_pixel_size: "色セル",
  image_fit: "配置", crop_position_x: "横位置", crop_position_y: "縦位置", crop_scale: "クロップ倍率",
  brightness: "明るさ", contrast: "コントラスト", saturation: "彩度", tile_count: "タイル数",
  tile_layout: "タイル配置", tile_rows: "行数", tile_columns: "列数", separate_z_parts: "Z分割",
  color_region_parts: "色領域数", minimum_thickness: "最小厚み", maximum_thickness: "最大厚み",
  nozzle_diameter: "ノズル", margin_top: "上余白", margin_right: "右余白",
  margin_bottom: "下余白", margin_left: "左余白"
};

let sourceUrl;
let previewId;
let stagePromise;
let selectionSequence = 0;
let renderSequence = 0;
let renderTimer;
let renderController;
let tileOverlayUrl;
let tileOverlayTimer;
let summaryTimer;
let summaryController;
let resolvedSummary;
let submitting = false;
let currentJobId = workspace?.dataset.selectedJob || undefined;
let activeJobId;
let activeJob;
let pollTimer;
let historyOffset = 0;
let historyTotal = 0;
const historyPageSize = 12;
const historyJobs = new Map();
const selectedJobIds = new Set();
let historySearchTimer;
let historyNotice;
let settingsLibrary = { schema_version: 1, presets: {}, draft: null };
let comparedJobs = [];
let aspectRatio = Number(document.querySelector("#width")?.value) / Number(document.querySelector("#height")?.value);
let submittedSignature;
let submittedSettings;
let displayedJob;
let dialogReturnFocus;
const appViewLabels = { create: "作成", jobs: "ジョブ", presets: "プリセット" };
let currentView = requestedView();
let currentJobDetailTab = requestedJobTab();

function requestedView() {
  const parameters = new URL(window.location.href).searchParams;
  const view = parameters.get("view");
  if (Object.hasOwn(appViewLabels, view)) return view;
  return parameters.has("job") ? "jobs" : "create";
}

function requestedJobTab() {
  const tab = new URL(window.location.href).searchParams.get("tab");
  return ["preview", "artifacts", "settings"].includes(tab) ? tab : "preview";
}

function viewUrl(view) {
  const parameters = new URLSearchParams();
  if (currentJobId) parameters.set("job", currentJobId);
  parameters.set("view", view);
  if (view === "jobs" && currentJobDetailTab !== "preview") parameters.set("tab", currentJobDetailTab);
  return `/?${parameters}`;
}

function closeNavigation() {
  document.body.classList.remove("navigation-open");
  document.querySelector("#menu-toggle")?.setAttribute("aria-expanded", "false");
}

function showAppView(view, { push = false, focus = false } = {}) {
  if (!Object.hasOwn(appViewLabels, view)) view = "create";
  currentView = view;
  workspace.dataset.view = view;
  document.querySelectorAll("[data-app-view]").forEach((candidate) => {
    candidate.hidden = candidate.dataset.appView !== view;
  });
  document.querySelectorAll("#primary-navigation [data-view-target]").forEach((button) => {
    if (button.dataset.viewTarget === view) button.setAttribute("aria-current", "page");
    else button.removeAttribute("aria-current");
  });
  document.querySelector("#current-view-label").textContent = appViewLabels[view];
  document.title = `${appViewLabels[view]} · Lithop Local UI`;
  closeNavigation();
  if (push) window.history.pushState({ jobId: currentJobId, view }, "", viewUrl(view));
  if (focus) document.querySelector(`[data-app-view="${view}"] .view-title`)?.focus({ preventScroll: true });
  window.requestAnimationFrame(() => viewerStates?.forEach?.((_state, id) => applyViewer(id)));
}

document.querySelectorAll("[data-view-target]").forEach((control) => {
  control.addEventListener("click", (event) => {
    event.preventDefault();
    showAppView(control.dataset.viewTarget, { push: currentView !== control.dataset.viewTarget, focus: true });
  });
});
document.querySelector("#menu-toggle")?.addEventListener("click", () => {
  const open = !document.body.classList.contains("navigation-open");
  document.body.classList.toggle("navigation-open", open);
  document.querySelector("#menu-toggle").setAttribute("aria-expanded", String(open));
  if (open) document.querySelector("#primary-navigation [aria-current='page']")?.focus();
});
document.querySelector("#navigation-scrim")?.addEventListener("click", closeNavigation);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && document.body.classList.contains("navigation-open")) {
    closeNavigation();
    document.querySelector("#menu-toggle")?.focus();
  }
});

function selectJobDetailTab(name, { focus = false, push = false } = {}) {
  const button = document.querySelector(`[data-job-tab="${name}"]`);
  if (!button) return;
  currentJobDetailTab = name;
  document.querySelectorAll("[data-job-tab]").forEach((candidate) => {
    candidate.setAttribute("aria-selected", String(candidate === button));
    candidate.tabIndex = candidate === button ? 0 : -1;
  });
  document.querySelectorAll("[data-job-panel]").forEach((panel) => {
    panel.hidden = panel.dataset.jobPanel !== name;
  });
  if (focus) button.focus();
  if (push) window.history.pushState({ jobId: currentJobId, view: "jobs", tab: name }, "", viewUrl("jobs"));
  window.requestAnimationFrame(() => {
    if (name === "preview") applyViewer("result-preview");
  });
}

document.querySelector("#job-detail-tabs")?.addEventListener("click", (event) => {
  const button = event.target.closest("[data-job-tab]");
  if (button) selectJobDetailTab(button.dataset.jobTab, { push: true });
});
document.querySelector("#job-detail-tabs")?.addEventListener("keydown", (event) => {
  if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
  const tabs = [...event.currentTarget.querySelectorAll("[data-job-tab]")];
  const offset = event.key === "ArrowRight" ? 1 : -1;
  const next = tabs[(tabs.indexOf(event.target) + offset + tabs.length) % tabs.length];
  event.preventDefault();
  selectJobDetailTab(next.dataset.jobTab, { focus: true, push: true });
});

document.querySelector("#help-button")?.addEventListener("click", () => {
  dialogReturnFocus = document.querySelector("#help-button");
  document.querySelector("#help-dialog").showModal();
});
document.querySelector("#close-help-dialog")?.addEventListener("click", () => document.querySelector("#help-dialog").close());
document.querySelector("#help-dialog")?.addEventListener("close", () => dialogReturnFocus?.focus());

function showSourceStatus(message) {
  sourcePlaceholder.textContent = message;
  sourcePlaceholder.hidden = false;
  sourceImage.hidden = true;
  document.querySelector('[data-expand-viewer="source-preview"]').disabled = true;
}

async function showSourceBlob(blob) {
  if (sourceUrl) URL.revokeObjectURL(sourceUrl);
  sourceUrl = URL.createObjectURL(blob);
  sourceImage.src = sourceUrl;
  try {
    await sourceImage.decode();
  } catch (_error) {
    // The image load/error handlers still provide the visible result.
  }
  sourceImage.hidden = false;
  sourcePlaceholder.hidden = true;
  document.querySelector('[data-expand-viewer="source-preview"]').disabled = false;
  resetViewer("source-preview");
}

async function responseError(response, fallback) {
  try {
    const payload = await response.json();
    return payload.error || fallback;
  } catch (_error) {
    return fallback;
  }
}

function settingParameters() {
  const values = new URLSearchParams();
  new FormData(form).forEach((value, key) => {
    if (key !== "image" && key !== "preview_id" && typeof value === "string") values.append(key, value);
  });
  return values;
}

function settingsSignature() {
  return settingParameters().toString();
}

function editableSettings() {
  return Object.fromEntries([...settingParameters()].filter(([key]) => key !== "csrf_token"));
}

function formatSetting(value, suffix = "") {
  return value === undefined || value === null || value === "" ? "自動" : `${value}${suffix}`;
}

function updateDraftSummary() {
  const values = editableSettings();
  const summary = document.querySelector("#draft-summary-values");
  const layoutLabels = { auto: "自動", columns: "横方向", rows: "縦方向", grid: "行列指定" };
  const resolvedLayout = resolvedSummary
    ? `${resolvedSummary.tile_rows}行 × ${resolvedSummary.tile_columns}列`
    : layoutLabels[values.tile_layout] || values.tile_layout;
  const z = separateZParts?.checked
    ? `色領域${values.color_region_parts} + Top White（${resolvedSummary?.z_plate_count || Number(values.color_region_parts) + 1}プレート）`
    : "一体出力";
  const entries = [
    ["入力", fileInput.files?.[0]?.name || "未選択"],
    ["完成寸法", `${formatSetting(values.width)} × ${formatSetting(values.height)} mm`],
    ["セル", `XY ${formatSetting(values.pixel_size, " mm")} / 色 ${formatSetting(values.color_pixel_size, " mm")}`],
    ["画像", `${values.image_fit === "contain" ? "全体を収める" : "全面に配置"} / 明るさ ${values.brightness}% / コントラスト ${values.contrast}% / 彩度 ${values.saturation}%`],
    ["分割", `${values.tile_count}タイル・${resolvedLayout}（${layoutLabels[values.tile_layout] || values.tile_layout}） / ${z}`]
  ];
  summary.replaceChildren();
  entries.forEach(([term, description]) => {
    const dt = document.createElement("dt");
    const dd = document.createElement("dd");
    dt.textContent = term;
    dd.textContent = description;
    summary.append(dt, dd);
  });
  const viewedSettings = displayedJob
    ? Object.fromEntries(Object.keys(values).filter((key) => key in displayedJob).map((key) => [key, displayedJob[key]]))
    : undefined;
  const baseline = submittedSettings || viewedSettings;
  const changed = baseline
    ? Object.keys(baseline).filter((key) => {
      const baselineValue = typeof baseline[key] === "boolean" ? (baseline[key] ? "1" : "") : String(baseline[key] ?? "");
      return baselineValue !== String(values[key] ?? "");
    })
    : [];
  const sourceChanged = Boolean(
    displayedJob?.input_name && fileInput.files?.[0] && fileInput.files[0].name !== displayedJob.input_name
  );
  const changeCount = changed.length + (sourceChanged ? 1 : 0);
  const state = document.querySelector("#draft-summary-change");
  state.textContent = baseline
    ? (changeCount ? `${changeCount}項目を編集中` : `${submittedSettings ? "実行時" : "表示中ジョブ"}の設定と一致`)
    : "未実行";
  state.dataset.changed = String(changeCount > 0);
}

function updateDraftState(message) {
  const state = document.querySelector("#draft-state");
  if (message) state.textContent = message;
  else if (!fileInput.files?.[0]) state.textContent = "画像を選択してください";
  else if (submittedSignature && submittedSignature !== settingsSignature()) state.textContent = "実行した設定から変更されています";
  else state.textContent = "入力プレビューに反映済み";
  updateDraftSummary();
  if (displayedJob) updateJobContext(displayedJob);
}

function showFormError(message) {
  const error = document.querySelector("#form-error");
  error.textContent = message;
  error.hidden = !message;
  if (message) error.scrollIntoView({ block: "nearest" });
}

async function discardPreview(id, keepalive = false) {
  if (!id) return;
  const values = new URLSearchParams({ csrf_token: csrfToken });
  try {
    await fetch(`/api/previews/${encodeURIComponent(id)}/discard`, { method: "POST", body: values, keepalive });
  } catch (_error) {
    // Expired preview inputs are recovered on the next local UI start.
  }
}

async function renderPreview(expectedId) {
  if (!expectedId || expectedId !== previewId) return;
  const requestNumber = ++renderSequence;
  renderController?.abort();
  renderController = new AbortController();
  showSourceStatus("プレビューを処理しています…");
  updateDraftState("プレビューを更新しています…");
  const startedAt = performance.now();
  try {
    const response = await fetch(`/api/previews/${encodeURIComponent(expectedId)}/render`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
      body: settingParameters(),
      signal: renderController.signal
    });
    const responseAt = performance.now();
    if (!response.ok) throw new Error(await responseError(response, "プレビューを生成できませんでした"));
    const blob = await response.blob();
    const transferredAt = performance.now();
    if (requestNumber !== renderSequence || expectedId !== previewId) return;
    await showSourceBlob(blob);
    const paintedAt = await new Promise((resolve) => window.requestAnimationFrame(() => resolve(performance.now())));
    window.dispatchEvent(new CustomEvent("lithop:preview-timing", { detail: {
      request_ms: responseAt - startedAt,
      transfer_ms: transferredAt - responseAt,
      decode_paint_ms: paintedAt - transferredAt,
      total_ms: paintedAt - startedAt,
      server_timing: response.headers.get("Server-Timing"),
      cache: response.headers.get("X-Lithop-Preview-Cache")
    } }));
    updateDraftState();
  } catch (error) {
    if (error.name !== "AbortError" && requestNumber === renderSequence) {
      showSourceStatus(`読み込み失敗: ${error.message}`);
      updateDraftState("プレビューを確認してください");
    }
  }
}

function schedulePreview(delay = 250) {
  window.clearTimeout(renderTimer);
  scheduleResolvedSummary(delay);
  if (!previewId) return;
  renderTimer = window.setTimeout(() => renderPreview(previewId), delay);
}

function scheduleResolvedSummary(delay = 250) {
  window.clearTimeout(summaryTimer);
  summaryTimer = window.setTimeout(refreshResolvedSummary, delay);
}

async function refreshResolvedSummary() {
  summaryController?.abort();
  summaryController = new AbortController();
  try {
    const response = await fetch("/api/settings-summary", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
      body: settingParameters(),
      signal: summaryController.signal
    });
    if (!response.ok) return;
    resolvedSummary = await response.json();
    updateDraftSummary();
  } catch (error) {
    if (error.name !== "AbortError") resolvedSummary = undefined;
  }
}

function scheduleTileOverlay(delay = 250) {
  window.clearTimeout(tileOverlayTimer);
  tileOverlayTimer = window.setTimeout(renderTileOverlay, delay);
}

async function renderTileOverlay() {
  const enabled = document.querySelector("#toggle-tile-overlay")?.checked;
  const count = Number(form.elements.tile_count.value);
  if (!enabled || count <= 1) {
    tileOverlay.hidden = true;
    return;
  }
  try {
    const response = await fetch("/api/tile-layout", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" },
      body: settingParameters()
    });
    if (!response.ok) throw new Error(await responseError(response, "タイル境界を表示できませんでした"));
    const blob = await response.blob();
    if (tileOverlayUrl) URL.revokeObjectURL(tileOverlayUrl);
    tileOverlayUrl = URL.createObjectURL(blob);
    tileOverlay.src = tileOverlayUrl;
    tileOverlay.hidden = false;
    applyViewer("source-preview");
  } catch (error) {
    tileOverlay.hidden = true;
    showFormError(error.message);
  }
}

function stageFile(file, { render = true } = {}) {
  const requestNumber = selectionSequence;
  const body = new FormData();
  body.append("csrf_token", csrfToken);
  body.append("image", file, file.name);
  const promise = fetch("/api/previews", { method: "POST", body })
    .then(async (response) => {
      if (!response.ok) throw new Error(await responseError(response, "画像を読み込めませんでした"));
      const payload = await response.json();
      if (requestNumber !== selectionSequence) {
        discardPreview(payload.id);
        return;
      }
      previewId = payload.id;
      previewIdInput.value = previewId;
      if (render) await renderPreview(previewId);
    })
    .catch((error) => {
      if (requestNumber === selectionSequence) {
        showSourceStatus(`読み込み失敗: ${error.message}`);
        showFormError(error.message);
      }
    })
    .finally(() => {
      if (stagePromise === promise) stagePromise = undefined;
    });
  stagePromise = promise;
  return promise;
}

function selectFile(file) {
  const oldPreviewId = previewId;
  selectionSequence += 1;
  previewId = undefined;
  previewIdInput.value = "";
  renderController?.abort();
  window.clearTimeout(renderTimer);
  discardPreview(oldPreviewId);
  showFormError("");
  if (!file) {
    fileName.textContent = "ファイルをここへ選択";
    showSourceStatus("画像未選択");
    updateDraftState();
    return;
  }

  fileName.textContent = file.name;
  const raster = file.type === "image/jpeg" || file.type === "image/png" || /\.(jpe?g|png)$/i.test(file.name);
  if (raster) showSourceBlob(file);
  else showSourceStatus("SVGを検証しています…");
  updateDraftState("画像を検証しています…");
  stageFile(file);
}

fileInput?.addEventListener("change", () => selectFile(fileInput.files?.[0]));
filePicker?.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    fileInput.click();
  }
});
["dragenter", "dragover"].forEach((name) => filePicker?.addEventListener(name, (event) => {
  event.preventDefault();
  filePicker.classList.add("is-dragging");
}));
["dragleave", "drop"].forEach((name) => filePicker?.addEventListener(name, (event) => {
  event.preventDefault();
  filePicker.classList.remove("is-dragging");
}));
filePicker?.addEventListener("drop", (event) => {
  const file = event.dataTransfer?.files?.[0];
  if (!file) return;
  const transfer = new DataTransfer();
  transfer.items.add(file);
  fileInput.files = transfer.files;
  selectFile(file);
});

function syncRanges() {
  document.querySelectorAll(".range-control").forEach((range) => {
    const number = document.getElementById(range.dataset.sync);
    range.value = number.value;
    range.addEventListener("input", () => {
      number.value = range.value;
      number.dispatchEvent(new Event("input", { bubbles: true }));
    });
    number.addEventListener("input", () => { range.value = number.value; });
  });
}

function updateGridFields() {
  const visible = tileLayout?.value === "grid";
  document.querySelectorAll(".grid-only").forEach((element) => {
    element.hidden = !visible;
    const input = element.querySelector("input");
    input.disabled = !visible;
    input.required = visible;
  });
}

function updateZFields() {
  const visible = separateZParts?.checked;
  const field = document.querySelector("#color-region-field");
  const input = document.querySelector("#color-region-parts");
  field.hidden = !visible;
  input.disabled = !visible;
  input.required = visible;
  document.querySelector("#z-parts-summary").textContent = visible
    ? `Base White付き色領域 ${input.value}プレート + Top White 1プレート`
    : "Z方向は一体のCMYWモデルとして出力します";
  const diagram = document.querySelector("#z-parts-diagram");
  diagram.replaceChildren();
  if (visible) {
    const partCount = Number(input.value);
    const size = Math.floor(7 / partCount);
    let remainder = 7 % partCount;
    let layer = 0;
    const labels = Array.from({ length: partCount }, (_value, index) => {
      const count = size + (remainder-- > 0 ? 1 : 0);
      const start = 0.2 + (layer * 0.1);
      layer += count;
      const finish = 0.2 + (layer * 0.1);
      return `色領域 ${index + 1}\n${start.toFixed(1)}–${finish.toFixed(1)} mm`;
    });
    labels.concat("Top White\n0.9 mm–可変上面").forEach((label) => {
      const part = document.createElement("span");
      part.textContent = label;
      diagram.append(part);
    });
  }
  diagram.hidden = !visible;
}

function updateDimensions() {
  const width = Number(document.querySelector("#width").value);
  const height = Number(document.querySelector("#height").value);
  document.querySelector("#preview-dimensions").textContent = `${width || "—"} × ${height || "—"} mm`;
  if (width > 0 && height > 0) document.querySelector("#source-preview").style.aspectRatio = `${width} / ${height}`;
}

tileLayout?.addEventListener("change", updateGridFields);
separateZParts?.addEventListener("change", updateZFields);
document.querySelector("#color-region-parts")?.addEventListener("input", updateZFields);
document.querySelector("#toggle-tile-overlay")?.addEventListener("change", () => scheduleTileOverlay(0));
syncRanges();
updateGridFields();
updateZFields();
updateDimensions();
updateDraftSummary();
refreshResolvedSummary();

const widthInput = document.querySelector("#width");
const heightInput = document.querySelector("#height");
const aspectLock = document.querySelector("#aspect-lock");
aspectLock?.addEventListener("change", () => {
  if (aspectLock.checked) aspectRatio = Number(widthInput.value) / Number(heightInput.value);
});
widthInput?.addEventListener("input", () => {
  if (aspectLock.checked && aspectRatio > 0 && document.activeElement === widthInput) heightInput.value = (Number(widthInput.value) / aspectRatio).toFixed(2);
  updateDimensions();
});
heightInput?.addEventListener("input", () => {
  if (aspectLock.checked && aspectRatio > 0 && document.activeElement === heightInput) widthInput.value = (Number(heightInput.value) * aspectRatio).toFixed(2);
  updateDimensions();
});
document.querySelector("#swap-dimensions")?.addEventListener("click", () => {
  const width = widthInput.value;
  widthInput.value = heightInput.value;
  heightInput.value = width;
  aspectRatio = Number(widthInput.value) / Number(heightInput.value);
  updateDimensions();
  schedulePreview(0);
  updateDraftState();
});

document.querySelectorAll(".section-reset").forEach((button) => {
  button.addEventListener("click", () => {
    button.closest("details").querySelectorAll("[data-default]").forEach((control) => {
      if (control.type === "checkbox") control.checked = control.dataset.default === "1";
      else control.value = control.dataset.default;
      control.dispatchEvent(new Event("change", { bubbles: true }));
    });
    syncRangesValues();
    updateDimensions();
    schedulePreview(0);
  });
});

function syncRangesValues() {
  document.querySelectorAll(".range-control").forEach((range) => {
    range.value = document.getElementById(range.dataset.sync).value;
  });
}

form?.addEventListener("input", (event) => {
  if (event.target !== fileInput) {
    schedulePreview();
    scheduleTileOverlay();
    updateDraftState();
  }
});
form?.addEventListener("change", (event) => {
  if (event.target !== fileInput) {
    schedulePreview();
    scheduleTileOverlay();
    updateDraftState();
  }
});
form?.addEventListener("invalid", (event) => {
  event.target.closest("details")?.setAttribute("open", "");
  const label = event.target.closest("label")?.childNodes?.[0]?.textContent?.trim();
  showFormError(`${label || "入力値"}を確認してください`);
}, true);

function setSubmitting(value) {
  submitting = value;
  const button = document.querySelector("#submit-button");
  button.disabled = value;
  button.textContent = value ? "変換を準備しています…" : "変換を開始";
}

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (submitting || !form.reportValidity()) return;
  setSubmitting(true);
  showFormError("");
  try {
    if (stagePromise) await stagePromise;
    const data = new FormData(form);
    if (previewId) {
      data.delete("image");
      data.set("preview_id", previewId);
    } else {
      data.delete("preview_id");
    }
    const snapshot = settingsSignature();
    const snapshotValues = editableSettings();
    const response = await fetch("/jobs", { method: "POST", headers: { Accept: "application/json" }, body: data });
    if (!response.ok) throw new Error(await responseError(response, "変換を開始できませんでした"));
    const payload = await response.json();
    submittedSignature = snapshot;
    submittedSettings = snapshotValues;
    currentJobId = payload.job_id;
    activeJobId = payload.job_id;
    activeJob = undefined;
    currentJobDetailTab = "preview";
    workspace.dataset.selectedJob = currentJobId;
    showAppView("jobs", { focus: true });
    window.history.pushState({ jobId: currentJobId, view: "jobs" }, "", viewUrl("jobs"));
    previewId = undefined;
    previewIdInput.value = "";
    showJobPanel(currentJobId);
    updateDraftState("この設定で変換を開始しました");
    refreshHistory();
    pollJob(currentJobId);
    const selectedFile = fileInput.files?.[0];
    if (selectedFile) stageFile(selectedFile, { render: false });
  } catch (error) {
    showFormError(error.message);
    setSubmitting(false);
  }
});

function settingsDifferences(values) {
  const current = editableSettings();
  return Object.entries(settingLabels).filter(([key]) => key in values).filter(([key]) => {
    const next = typeof values[key] === "boolean" ? (values[key] ? "1" : "") : String(values[key] ?? "");
    return next !== String(current[key] ?? "");
  }).map(([key, label]) => ({ key, label, before: current[key] ?? "自動", after: values[key] ?? "自動" }));
}

function applySettings(values, sourceLabel) {
  const differences = settingsDifferences(values);
  const detail = differences.length
    ? differences.map((difference) => `${difference.label}: ${difference.before} → ${difference.after}`).join("\n")
    : "現在の設定との差はありません。";
  if (!window.confirm(`${sourceLabel}を編集へ読み込みます。\n\n${detail}`)) return false;
  Object.entries(settingLabels).forEach(([key]) => {
    if (!(key in values)) return;
    const control = form.elements.namedItem(key);
    if (!control) return;
    if (control.type === "checkbox") control.checked = values[key] === true || values[key] === "1";
    else control.value = values[key] === null ? "" : String(values[key]);
  });
  updateGridFields();
  updateZFields();
  syncRangesValues();
  updateDimensions();
  schedulePreview(0);
  scheduleTileOverlay(0);
  refreshResolvedSummary();
  updateDraftState(fileInput.files?.[0]
    ? `${sourceLabel}を反映しました。入力画像は保持されています`
    : `${sourceLabel}を反映しました。画像を選択してください`);
  document.querySelector("#settings-library-status").textContent = fileInput.files?.[0]
    ? `${sourceLabel}を反映しました。入力画像は変更していません。`
    : `${sourceLabel}を反映しました。画像は保存されないため、選択してください。`;
  showAppView("create", { push: currentView !== "create", focus: true });
  return true;
}

async function settingsLibraryRequest(path, values = new URLSearchParams()) {
  values.set("csrf_token", csrfToken);
  const response = await fetch(path, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" }, body: values
  });
  if (!response.ok) throw new Error(await responseError(response, "設定を保存できませんでした"));
  settingsLibrary = await response.json();
  renderSettingsLibrary();
  return settingsLibrary;
}

function renderSettingsLibrary() {
  const select = document.querySelector("#preset-select");
  const selected = select.value;
  select.replaceChildren(new Option("プリセットを選択", ""));
  Object.keys(settingsLibrary.presets || {}).forEach((name) => select.add(new Option(name, name)));
  if (settingsLibrary.presets?.[selected]) select.value = selected;
  document.querySelector("#draft-restore").disabled = !settingsLibrary.draft;
  document.querySelector("#draft-delete").disabled = !settingsLibrary.draft;
}

async function loadSettingsLibrary() {
  try {
    const response = await fetch("/api/settings-library", { cache: "no-store" });
    if (!response.ok) throw new Error(await responseError(response, "保存設定を読み込めませんでした"));
    settingsLibrary = await response.json();
    renderSettingsLibrary();
  } catch (error) {
    document.querySelector("#settings-library-status").textContent = error.message;
  }
}

document.querySelector("#preset-select")?.addEventListener("change", (event) => {
  document.querySelector("#preset-name").value = event.target.value;
});
document.querySelector("#preset-save")?.addEventListener("click", async () => {
  try {
    const values = settingParameters();
    const name = document.querySelector("#preset-name").value.trim();
    values.set("name", name);
    await settingsLibraryRequest("/api/settings-library/presets", values);
    document.querySelector("#preset-select").value = name;
    document.querySelector("#settings-library-status").textContent = `「${name}」へ現在設定を保存しました。画像は保存していません。`;
  } catch (error) { showFormError(error.message); }
});
document.querySelector("#preset-load")?.addEventListener("click", () => {
  const name = document.querySelector("#preset-select").value;
  const preset = settingsLibrary.presets?.[name];
  if (!preset) return showFormError("読み込むプリセットを選択してください");
  applySettings(preset.settings, `プリセット「${name}」`);
});
document.querySelector("#preset-rename")?.addEventListener("click", async () => {
  const name = document.querySelector("#preset-select").value;
  const newName = document.querySelector("#preset-name").value.trim();
  if (!name) return showFormError("名前を変更するプリセットを選択してください");
  try {
    await settingsLibraryRequest("/api/settings-library/presets/rename", new URLSearchParams({ name, new_name: newName }));
    document.querySelector("#preset-select").value = newName;
    document.querySelector("#settings-library-status").textContent = `「${name}」を「${newName}」へ変更しました。`;
  } catch (error) { showFormError(error.message); }
});
document.querySelector("#preset-delete")?.addEventListener("click", async () => {
  const name = document.querySelector("#preset-select").value;
  if (!name) return showFormError("削除するプリセットを選択してください");
  if (!window.confirm(`プリセット「${name}」を削除します。`)) return;
  try {
    await settingsLibraryRequest("/api/settings-library/presets/delete", new URLSearchParams({ name }));
    document.querySelector("#preset-name").value = "";
    document.querySelector("#settings-library-status").textContent = `「${name}」を削除しました。`;
  } catch (error) { showFormError(error.message); }
});
document.querySelector("#draft-save")?.addEventListener("click", async () => {
  try {
    await settingsLibraryRequest("/api/settings-library/draft", settingParameters());
    document.querySelector("#settings-library-status").textContent = "下書き設定を保存しました。画像は保存していません。";
  } catch (error) { showFormError(error.message); }
});
document.querySelector("#draft-restore")?.addEventListener("click", () => {
  if (settingsLibrary.draft) applySettings(settingsLibrary.draft.settings, "下書き設定");
});
document.querySelector("#draft-delete")?.addEventListener("click", async () => {
  try {
    await settingsLibraryRequest("/api/settings-library/draft/delete");
    document.querySelector("#settings-library-status").textContent = "下書き設定を削除しました。";
  } catch (error) { showFormError(error.message); }
});
document.querySelector("#load-job-settings")?.addEventListener("click", () => {
  if (displayedJob) applySettings(displayedJob, `ジョブ ${displayedJob.job_id} の設定`);
});

function formatBytes(value) {
  const bytes = Number(value) || 0;
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function jobSnapshot(job) {
  const values = [];
  if (job.input_name) values.push(job.input_name);
  if (job.created_at) values.push(new Date(job.created_at).toLocaleString("ja-JP"));
  if (job.width && job.height) values.push(`${job.width} × ${job.height} mm`);
  if (job.tile_count) values.push(`${job.tile_count}タイル`);
  if (job.separate_z_parts) values.push("Z分割");
  return values.join(" · ");
}

function jobSettingDifferences(job) {
  const current = editableSettings();
  return Object.entries(settingLabels).filter(([key]) => {
    if (!(key in job)) return false;
    const jobValue = typeof job[key] === "boolean" ? (job[key] ? "1" : "") : String(job[key] ?? "");
    return jobValue !== String(current[key] ?? "");
  }).map(([, label]) => label);
}

function updateJobContext(job) {
  document.querySelector("#job-view-name").textContent = job.input_name || "入力名の記録がないジョブ";
  const differences = jobSettingDifferences(job);
  const snapshot = jobSnapshot(job);
  document.querySelector("#job-settings-snapshot").textContent = differences.length
    ? `${snapshot} · 編集中と異なる項目: ${differences.join("、")}`
    : `${snapshot} · 編集中の設定と一致`;
}

function updateGlobalJob(job) {
  const control = document.querySelector("#global-job-control");
  const representedJob = job || activeJob;
  const representedId = representedJob?.job_id || activeJobId || currentJobId;
  if (!representedId) {
    control.hidden = true;
    return;
  }
  const state = representedJob?.state || "queued";
  const percent = Math.round(Number(representedJob?.percent) || 0);
  control.hidden = false;
  const inputName = representedJob?.input_name;
  document.querySelector("#global-job-label").textContent = `${inputName ? `${inputName} · ` : ""}${representedId} · ${stateLabels[state] || state}`;
  document.querySelector("#global-job-percent").textContent = `${percent}%`;
  const cancel = document.querySelector("#global-cancel-button");
  cancel.hidden = !["queued", "running", "cancelling"].includes(state);
  cancel.disabled = state === "cancelling";
  cancel.textContent = state === "cancelling" ? "停止要求中" : "停止";
}

function showJobPanel(jobId) {
  const panel = document.querySelector("#job-panel");
  displayedJob = undefined;
  workspace.classList.add("has-job");
  panel.hidden = false;
  document.querySelector("#job-id").textContent = jobId;
  document.querySelector("#job-view-name").textContent = "ジョブを読み込んでいます";
  document.querySelector("#job-state").textContent = "待機中";
  document.querySelector("#job-percent").textContent = "0%";
  document.querySelector("#job-message").textContent = "変換を開始しています";
  document.querySelector("#progress-bar").style.width = "0%";
  document.querySelector("#result-layout").hidden = true;
  document.querySelector("#job-error").hidden = true;
  document.querySelector("#delete-button").hidden = true;
  document.querySelector("#cancel-button").hidden = false;
  document.querySelector("#job-connection").textContent = "状態を取得しています";
  document.querySelector("#job-connection").dataset.connection = "loading";
  document.querySelector("#job-updated-at").textContent = "";
  document.querySelector("#retry-status-button").hidden = true;
  document.querySelector("#job-detail-tabs").hidden = true;
  selectJobDetailTab(currentJobDetailTab);
  workspace.classList.remove("show-job-list");
  updateGlobalJob();
  panel.scrollIntoView({ block: "start" });
}

function formatElapsed(start) {
  if (!start) return "";
  const seconds = Math.max(0, Math.round((Date.now() - new Date(start).getTime()) / 1000));
  if (seconds < 60) return `${seconds}秒経過`;
  const minutes = Math.floor(seconds / 60);
  return `${minutes}分${seconds % 60}秒経過`;
}

function showConnection(state, message) {
  const connection = document.querySelector("#job-connection");
  connection.dataset.connection = state;
  connection.textContent = message;
  document.querySelector("#retry-status-button").hidden = state !== "offline";
}

function resultPreviews(job) {
  const artifacts = new Map(job.artifacts.map((artifact) => [artifact.name, artifact]));
  return previewKinds.map(({ name }) => artifacts.get(name)).filter(Boolean);
}

function selectResultPreview(artifact, button) {
  document.querySelectorAll("#result-tabs button").forEach((candidate) => candidate.setAttribute("aria-selected", String(candidate === button)));
  document.querySelector("#result-image").src = `${artifact.url}?v=${encodeURIComponent(currentJobId || "result")}`;
  document.querySelector("#result-caption").textContent = previewLabels[artifact.name];
  resetViewer("result-preview");
}

function setBambuOpenStatus(message, state = "") {
  const status = document.querySelector("#bambu-open-status");
  status.textContent = message;
  status.dataset.state = state;
}

async function openInBambuStudio(jobId, artifact, button) {
  const initialLabel = button.textContent;
  button.disabled = true;
  button.textContent = "起動を要求中…";
  if (currentJobId === jobId) setBambuOpenStatus(`${artifact.name} をBambu Studioへ渡しています`);
  try {
    const body = new URLSearchParams({ name: artifact.name });
    const response = await fetch(`/api/jobs/${encodeURIComponent(jobId)}/open-in-bambu-studio`, {
      method: "POST", headers: { "X-CSRF-Token": csrfToken }, body
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(payload.error || "Bambu Studioを開けませんでした");
    if (currentJobId === jobId) {
      setBambuOpenStatus(`${artifact.name} をBambu Studioに渡しました。表示されない場合は3MFを保存して開いてください。`, "success");
    }
  } catch (error) {
    if (currentJobId === jobId) setBambuOpenStatus(error.message, "error");
  } finally {
    if (button.isConnected) {
      button.disabled = false;
      button.textContent = initialLabel;
    }
  }
}

function bambuOpenButton(job, artifact) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "secondary-button bambu-open-button";
  button.textContent = "Bambu Studioで開く";
  button.setAttribute("aria-label", `${artifact.name}をBambu Studioで開く`);
  button.addEventListener("click", (event) => {
    event.stopPropagation();
    openInBambuStudio(job.job_id, artifact, button);
  });
  return button;
}

function renderTileModels(job) {
  const section = document.querySelector("#tile-results");
  const list = document.querySelector("#tile-result-list");
  const models = job.artifacts.filter((artifact) => /(?:^|\/)tile_[^/]+\.3mf$/i.test(artifact.name));
  const previews = new Map(job.artifacts.map((artifact) => [artifact.name, artifact]));
  const metadata = new Map((job.tiles || []).map((tile) => [tile.file, tile]));
  const plateCount = job.z_part_separation?.enabled
    ? (job.z_part_separation.color_regions?.length || 0) + 1
    : 1;
  list.replaceChildren();
  section.querySelector(".tile-map")?.remove();
  const selectTile = (tileId, { move = false } = {}) => {
    section.querySelectorAll("[data-tile-id]").forEach((element) => {
      const selected = element.dataset.tileId === tileId;
      element.classList.toggle("is-selected", selected);
      if (element.matches("button")) element.setAttribute("aria-pressed", String(selected));
    });
    if (move) document.getElementById(`tile-card-${tileId}`)?.scrollIntoView({ block: "nearest" });
  };
  if (models.length > 1) {
    const map = document.createElement("div");
    map.className = "tile-map";
    map.setAttribute("aria-label", "タイル全体図");
    const rows = new Map();
    models.forEach((model) => {
      const tile = metadata.get(model.name);
      const tileId = tile?.id || model.name.split("/").pop().replace(/\.3mf$/i, "");
      const button = document.createElement("button");
      button.type = "button";
      button.dataset.tileId = tileId;
      button.textContent = tileId.replace("tile_", "");
      button.setAttribute("aria-label", `${tileId}を表示`);
      button.addEventListener("click", () => selectTile(tileId, { move: true }));
      const rowNumber = tile?.row || 1;
      if (!rows.has(rowNumber)) {
        const row = document.createElement("div");
        row.className = "tile-map-row";
        rows.set(rowNumber, row);
        map.append(row);
      }
      rows.get(rowNumber).append(button);
    });
    list.before(map);
  }
  models.forEach((model) => {
    const previewName = model.name.replace(/\.3mf$/i, "-preview.png");
    const preview = previews.get(previewName);
    const tile = metadata.get(model.name);
    const tileId = tile?.id || model.name.split("/").pop().replace(/\.3mf$/i, "");
    const card = document.createElement("figure");
    card.className = "tile-result-card";
    card.id = `tile-card-${tileId}`;
    card.dataset.tileId = tileId;
    card.tabIndex = 0;
    card.addEventListener("click", () => selectTile(tileId));
    card.addEventListener("keydown", (event) => {
      if (event.target.closest("button, a")) return;
      if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        selectTile(tileId);
      }
    });
    if (preview) {
      const image = document.createElement("img");
      image.src = `${preview.url}?v=${encodeURIComponent(currentJobId || "result")}`;
      image.alt = `${model.name} のプレビュー`;
      image.loading = "lazy";
      card.append(image);
    } else {
      const missing = document.createElement("div");
      missing.className = "tile-preview-missing";
      missing.textContent = "プレビューなし";
      card.append(missing);
    }
    const caption = document.createElement("figcaption");
    const name = document.createElement("strong");
    name.textContent = tileId;
    const link = document.createElement("a");
    link.href = model.url;
    link.download = model.name.split("/").pop();
    link.textContent = "3MFを保存";
    const actions = document.createElement("div");
    actions.className = "tile-model-actions";
    actions.append(link);
    if (job.can_open_in_bambu_studio) actions.append(bambuOpenButton(job, model));
    caption.append(name, actions);
    card.append(caption);
    if (tile) {
      const details = document.createElement("small");
      const dimensions = tile.dimensions_mm || {};
      const offset = tile.offset_mm || {};
      details.textContent = `行${tile.row}・列${tile.column} · ${dimensions.width} × ${dimensions.height} mm · 配置 (${offset.x}, ${offset.y}) mm · ${plateCount}プレート`;
      card.append(details);
    }
    list.append(card);
  });
  section.hidden = models.length < 2;
  const first = section.querySelector("[data-tile-id]");
  if (first) selectTile(first.dataset.tileId);
}

function renderArtifacts(job) {
  const layout = document.querySelector("#result-layout");
  const list = document.querySelector("#artifact-list");
  const tabs = document.querySelector("#result-tabs");
  list.replaceChildren();
  tabs.replaceChildren();
  setBambuOpenStatus(job.can_open_in_bambu_studio ? "3MFは保存するか、Bambu Studioで直接開けます。" : "");
  renderTileModels(job);
  const groups = { "モデル": [], "画像・配置": [], "設定・記録": [], "印刷説明": [] };
  job.artifacts.forEach((artifact) => {
    if (/\.(3mf|stl)$/i.test(artifact.name)) groups["モデル"].push(artifact);
    else if (/\.(png|svg)$/i.test(artifact.name)) groups["画像・配置"].push(artifact);
    else if (/PRINT_README/i.test(artifact.name)) groups["印刷説明"].push(artifact);
    else groups["設定・記録"].push(artifact);
  });
  document.querySelector("#download-models").disabled = !job.artifacts.some((artifact) => /\.3mf$/i.test(artifact.name));
  document.querySelector("#download-all").disabled = job.artifacts.length === 0;
  Object.entries(groups).forEach(([label, artifacts]) => {
    if (!artifacts.length) return;
    const group = document.createElement("li");
    const title = document.createElement("strong");
    title.textContent = label;
    const entries = document.createElement("ul");
    artifacts.forEach((artifact) => {
      const item = document.createElement("li");
      const link = document.createElement("a");
      link.href = artifact.url;
      link.textContent = artifact.name;
      if (artifact.name.endsWith(".3mf") || artifact.name.endsWith(".stl")) link.download = artifact.name;
      if (/\.3mf$/i.test(artifact.name) && job.can_open_in_bambu_studio) {
        const actions = document.createElement("div");
        actions.className = "artifact-actions";
        actions.append(link, bambuOpenButton(job, artifact));
        item.append(actions);
      } else {
        item.append(link);
      }
      entries.append(item);
    });
    group.append(title, entries);
    list.append(group);
  });
  const previews = resultPreviews(job);
  previews.forEach((artifact, index) => {
    const kind = previewKinds.find(({ name }) => name === artifact.name);
    const button = document.createElement("button");
    button.type = "button";
    button.role = "tab";
    button.textContent = kind.label;
    button.title = kind.description;
    button.setAttribute("aria-selected", String(index === 0));
    button.addEventListener("click", () => selectResultPreview(artifact, button));
    tabs.append(button);
  });
  if (previews[0]) selectResultPreview(previews[0], tabs.firstElementChild);
  tabs.hidden = previews.length < 2;
  const correctedFigure = document.querySelector(".comparison-source").closest("figure");
  const unavailable = document.querySelector("#corrected-input-unavailable");
  correctedFigure.hidden = !job.corrected_input_url;
  unavailable.hidden = Boolean(job.corrected_input_url);
  if (job.corrected_input_url) {
    compareSourceImage.src = `${job.corrected_input_url}?v=${encodeURIComponent(currentJobId || "result")}`;
  } else {
    compareSourceImage.removeAttribute("src");
  }
  layout.hidden = false;
}

async function downloadArchive(scope) {
  if (!currentJobId) return;
  const button = document.querySelector(scope === "models" ? "#download-models" : "#download-all");
  button.disabled = true;
  try {
    const response = await fetch(`/api/jobs/${encodeURIComponent(currentJobId)}/archive-summary?scope=${scope}`, { cache: "no-store" });
    if (!response.ok) throw new Error(await responseError(response, "ZIPの対象を確認できませんでした"));
    const summary = await response.json();
    const files = summary.files.map((file) => `${file.name}（${formatBytes(file.size_bytes)}）`).join("\n");
    if (!window.confirm(`${summary.file_count}ファイル（${formatBytes(summary.size_bytes)}）をZIPで取得します。\n\n${files}`)) return;
    const link = document.createElement("a");
    link.href = summary.download_url;
    link.download = `${currentJobId}-${scope}.zip`;
    document.body.append(link);
    link.click();
    link.remove();
  } catch (error) {
    showFormError(error.message);
  } finally {
    button.disabled = false;
  }
}

document.querySelector("#download-models")?.addEventListener("click", () => downloadArchive("models"));
document.querySelector("#download-all")?.addEventListener("click", () => downloadArchive("all"));

function updateResultAspect(job) {
  const width = Number(job.width);
  const height = Number(job.height);
  if (!(width > 0 && height > 0)) return;
  document.querySelectorAll(".comparison-grid .result-preview").forEach((preview) => {
    preview.style.aspectRatio = `${width} / ${height}`;
  });
}

function renderJobSettingDetails(job) {
  const details = document.querySelector("#job-setting-details");
  details.replaceChildren();
  const entries = [
    ["入力", job.input_name || "記録なし"],
    ["ジョブID", job.job_id],
    ["作成日時", job.created_at ? new Date(job.created_at).toLocaleString("ja-JP") : "記録なし"],
    ...Object.entries(settingLabels).filter(([key]) => key in job).map(([key, label]) => [label, formatSetting(job[key])])
  ];
  entries.forEach(([label, value]) => {
    const term = document.createElement("dt");
    const description = document.createElement("dd");
    term.textContent = label;
    description.textContent = value;
    details.append(term, description);
  });
  const log = document.querySelector("#job-detail-log-link");
  log.hidden = !job.log_url;
  if (job.log_url) log.href = job.log_url;
}

function renderJob(job) {
  const percent = Math.round(Number(job.percent) || 0);
  document.querySelector("#job-state").textContent = stateLabels[job.state] || job.state;
  document.querySelector("#job-state").dataset.state = job.state;
  document.querySelector("#job-percent").textContent = `${percent}%`;
  document.querySelector("#job-message").textContent = job.message || job.phase || "";
  displayedJob = job;
  const active = ["queued", "running", "cancelling"].includes(job.state);
  if (active && !activeJobId) activeJobId = job.job_id;
  if (job.job_id === activeJobId) {
    activeJob = job;
    updateGlobalJob(job);
    if (!active) activeJobId = undefined;
  } else if (!activeJobId) {
    updateGlobalJob(job);
  }
  updateJobContext(job);
  renderJobSettingDetails(job);
  updateDraftSummary();
  updateResultAspect(job);
  const thickness = job.minimum_thickness && job.maximum_thickness
    ? `厚み画像: ${job.minimum_thickness}–${job.maximum_thickness} mm。`
    : "";
  document.querySelector("#result-legend").textContent = `${thickness}材料マスクは白が0層、濃い部分ほどその材料の層数が多い領域です。`;
  document.querySelector("#progress-bar").style.width = `${percent}%`;
  document.querySelector(".progress-track").setAttribute("aria-valuenow", String(percent));
  const updated = job.updated_at ? new Date(job.updated_at).toLocaleString("ja-JP") : "時刻の記録なし";
  const elapsed = active ? formatElapsed(job.started_at || job.created_at) : "";
  document.querySelector("#job-updated-at").textContent = `最終更新 ${updated}${elapsed ? ` · ${elapsed}` : ""}`;
  showConnection("online", active ? "接続中・状態を自動更新" : "最新状態を取得済み");
  const cancel = document.querySelector("#cancel-button");
  cancel.hidden = !active;
  cancel.disabled = job.state === "cancelling";
  cancel.textContent = job.state === "cancelling" ? "停止要求中…" : "停止";
  const final = ["completed", "failed", "cancelled"].includes(job.state);
  document.querySelector("#job-detail-tabs").hidden = job.state !== "completed";
  document.querySelector("#load-job-settings").hidden = !Object.keys(settingLabels).some((key) => key in job);
  const remove = document.querySelector("#delete-button");
  remove.hidden = !final;
  remove.dataset.fileCount = job.file_count || 0;
  remove.dataset.sizeBytes = job.size_bytes || 0;
  const summary = document.querySelector("#delete-summary");
  summary.textContent = `${job.file_count || 0}ファイル・${formatBytes(job.size_bytes)}`;
  summary.hidden = !final;
  if (job.state === "completed") renderArtifacts(job);
  const error = document.querySelector("#job-error");
  const logLink = document.querySelector("#job-log-link");
  if (job.state === "failed" || job.state === "cancelled") {
    const guidance = job.state === "failed" ? "画像または設定を確認して、もう一度変換できます。" : "編集内容は保持されています。";
    document.querySelector("#job-error-message").textContent = `${job.error?.message || job.message} ${guidance}`;
    logLink.hidden = !job.log_url;
    if (job.log_url) logLink.href = job.log_url;
    error.hidden = false;
  } else {
    logLink.hidden = true;
    error.hidden = true;
  }
  if (final) setSubmitting(false);
  return active;
}

async function fetchJob(jobId) {
  const response = await fetch(`/api/jobs/${encodeURIComponent(jobId)}`, { cache: "no-store" });
  if (response.status === 404) return null;
  if (!response.ok) throw new Error("ジョブ状態を取得できませんでした");
  return response.json();
}

async function pollJob(jobId) {
  window.clearTimeout(pollTimer);
  try {
    const job = await fetchJob(jobId);
    if (!job) {
      if (jobId === currentJobId) {
        document.querySelector("#job-message").textContent = "ジョブは削除されました";
        showConnection("online", "ジョブは別の画面で削除されました");
      }
      return;
    }
    const isActiveJob = jobId === activeJobId;
    const active = ["queued", "running", "cancelling"].includes(job.state);
    if (isActiveJob) {
      activeJob = job;
      updateGlobalJob(job);
      if (!active) activeJobId = undefined;
    }
    if (jobId === currentJobId) renderJob(job);
    if (active && (isActiveJob || jobId === currentJobId)) pollTimer = window.setTimeout(() => pollJob(jobId), 900);
    refreshHistory();
  } catch (error) {
    if (jobId === currentJobId) showConnection("offline", `通信できません: ${error.message}`);
    if (jobId === activeJobId || jobId === currentJobId) pollTimer = window.setTimeout(() => pollJob(jobId), 1800);
  }
}

async function selectJob(jobId, { push = true, navigate = true } = {}) {
  if (push) currentJobDetailTab = "preview";
  currentJobId = jobId;
  workspace.dataset.selectedJob = jobId;
  if (navigate) showAppView("jobs", { focus: push });
  showJobPanel(jobId);
  try {
    const job = await fetchJob(jobId);
    if (!job) {
      document.querySelector("#job-message").textContent = "ジョブは見つかりません";
      showConnection("online", "ジョブは削除された可能性があります");
      return;
    }
    if (["queued", "running", "cancelling"].includes(job.state) && !activeJobId) {
      activeJobId = job.job_id;
      activeJob = job;
    }
    renderJob(job);
    if (push) window.history.pushState({ jobId, view: "jobs" }, "", viewUrl("jobs"));
    if (["queued", "running", "cancelling"].includes(job.state)) pollJob(jobId);
  } catch (error) {
    showConnection("offline", `通信できません: ${error.message}`);
  }
}

async function deleteJob(jobId, button) {
  const count = button.dataset.fileCount || "0";
  const size = formatBytes(button.dataset.sizeBytes);
  if (!window.confirm(`${jobId} の${count}ファイル（${size}）を削除します。元に戻せません。`)) return;
  button.disabled = true;
  try {
    const response = await fetch(`/jobs/${encodeURIComponent(jobId)}/delete`, { method: "POST", headers: { "X-CSRF-Token": csrfToken } });
    if (!response.ok) throw new Error(await responseError(response, "ジョブを削除できませんでした"));
    if (jobId === activeJobId || jobId === activeJob?.job_id) {
      activeJobId = undefined;
      activeJob = undefined;
    }
    if (jobId === currentJobId) {
      window.clearTimeout(pollTimer);
      currentJobId = undefined;
      displayedJob = undefined;
      workspace.dataset.selectedJob = "";
      workspace.classList.remove("has-job");
      document.querySelector("#job-panel").hidden = true;
      updateGlobalJob();
      window.history.pushState({ view: "jobs" }, "", "/?view=jobs");
    }
    await refreshHistory();
  } catch (error) {
    button.disabled = false;
    showFormError(error.message);
  }
}

function updateHistorySelection() {
  const selected = [...selectedJobIds].map((id) => historyJobs.get(id)).filter(Boolean);
  const completed = selected.filter((job) => job.state === "completed");
  const final = selected.filter((job) => ["completed", "failed", "cancelled"].includes(job.state));
  const size = selected.reduce((sum, job) => sum + Number(job.size_bytes || 0), 0);
  document.querySelector("#history-selection-status").textContent = selected.length
    ? `${selected.length}件選択・${formatBytes(size)}` : (historyNotice || "未選択");
  document.querySelector("#compare-jobs").disabled = selected.length !== 2 || completed.length !== 2;
  document.querySelector("#delete-selected-jobs").disabled = selected.length === 0 || final.length !== selected.length;
}

function renderHistory() {
  const list = document.querySelector("#job-list");
  list.replaceChildren();
  historyJobs.forEach((job) => {
    const item = document.createElement("li");
    item.dataset.state = job.state;
    if (["completed", "failed", "cancelled"].includes(job.state)) {
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.className = "history-select";
      checkbox.dataset.jobId = job.job_id;
      checkbox.checked = selectedJobIds.has(job.job_id);
      checkbox.setAttribute("aria-label", `${job.input_name || job.job_id}を選択`);
      item.append(checkbox);
    }
    const link = document.createElement("a");
    link.href = `/?job=${encodeURIComponent(job.job_id)}&view=jobs`;
    link.dataset.jobId = job.job_id;
    const title = document.createElement("strong");
    title.textContent = job.input_name || job.job_id;
    const id = document.createElement("span");
    id.textContent = job.job_id;
    const details = document.createElement("small");
    const size = job.width && job.height ? ` · ${job.width} × ${job.height} mm` : "";
    const tiles = job.tile_count ? ` · ${job.tile_count}タイル` : "";
    const date = job.created_at ? ` · ${new Date(job.created_at).toLocaleString("ja-JP")}` : "";
    details.textContent = `${stateLabels[job.state] || job.state} · ${Math.round(Number(job.percent) || 0)}%${size}${tiles}${date}`;
    if (job.preview_url) {
      const thumbnail = document.createElement("img");
      thumbnail.className = "history-thumbnail";
      thumbnail.src = job.preview_url;
      thumbnail.alt = "";
      thumbnail.loading = "lazy";
      link.append(thumbnail);
    }
    link.append(title, id, details);
    item.append(link);
    if (["completed", "failed", "cancelled"].includes(job.state)) {
      const remove = document.createElement("button");
      remove.type = "button";
      remove.className = "history-delete";
      remove.textContent = "削除";
      remove.dataset.jobId = job.job_id;
      remove.dataset.fileCount = job.file_count || 0;
      remove.dataset.sizeBytes = job.size_bytes || 0;
      item.append(remove);
    }
    list.append(item);
  });
  document.querySelector("#history-empty").hidden = historyJobs.size > 0;
  document.querySelector("#history-empty").textContent = historyTotal ? "条件に一致するジョブはありません。" : "まだジョブはありません。";
  document.querySelector("#load-more-jobs").hidden = historyJobs.size >= historyTotal;
  updateHistorySelection();
}

function historyRequestParameters() {
  return new URLSearchParams({
    limit: String(historyPageSize), offset: String(historyOffset),
    q: document.querySelector("#history-query").value,
    state: document.querySelector("#history-filter").value,
    date_from: document.querySelector("#history-date-from").value,
    date_to: document.querySelector("#history-date-to").value,
    sort: document.querySelector("#history-sort").value
  });
}

async function refreshHistory({ append = false } = {}) {
  try {
    if (!append) historyOffset = 0;
    const response = await fetch(`/api/jobs?${historyRequestParameters()}`, { cache: "no-store" });
    if (!response.ok) return;
    const payload = await response.json();
    if (!append) historyJobs.clear();
    payload.jobs.forEach((job) => historyJobs.set(job.job_id, job));
    const active = payload.jobs.find((job) => ["queued", "running", "cancelling"].includes(job.state));
    if (active && !activeJobId) {
      activeJobId = active.job_id;
      activeJob = active;
      updateGlobalJob(active);
      pollJob(active.job_id);
    }
    historyTotal = payload.total;
    historyOffset = historyJobs.size;
    [...selectedJobIds].forEach((id) => {
      if (!historyJobs.has(id) && !append) selectedJobIds.delete(id);
    });
    renderHistory();
  } catch (_error) {
    // The selected job poll reports connection failures.
  }
}

document.querySelector("#job-list")?.addEventListener("click", (event) => {
  const checkbox = event.target.closest(".history-select");
  if (checkbox) {
    historyNotice = undefined;
    if (checkbox.checked) selectedJobIds.add(checkbox.dataset.jobId);
    else selectedJobIds.delete(checkbox.dataset.jobId);
    updateHistorySelection();
    return;
  }
  const remove = event.target.closest(".history-delete");
  if (remove) {
    event.preventDefault();
    deleteJob(remove.dataset.jobId, remove);
    return;
  }
  const link = event.target.closest("a[data-job-id]");
  if (link) {
    event.preventDefault();
    selectJob(link.dataset.jobId);
  }
});
document.querySelectorAll("#history-filter, #history-date-from, #history-date-to, #history-sort").forEach((control) => {
  control.addEventListener("change", () => refreshHistory());
});
document.querySelector("#history-query")?.addEventListener("input", () => {
  window.clearTimeout(historySearchTimer);
  historySearchTimer = window.setTimeout(() => refreshHistory(), 250);
});
document.querySelector("#load-more-jobs")?.addEventListener("click", () => refreshHistory({ append: true }));

document.querySelector("#delete-selected-jobs")?.addEventListener("click", async () => {
  const jobs = [...selectedJobIds].map((id) => historyJobs.get(id)).filter(Boolean);
  const size = jobs.reduce((sum, job) => sum + Number(job.size_bytes || 0), 0);
  if (!window.confirm(`${jobs.length}件（${formatBytes(size)}）を削除します。元に戻せません。\n\n${jobs.map((job) => job.job_id).join("\n")}`)) return;
  const values = new URLSearchParams({ csrf_token: csrfToken });
  jobs.forEach((job) => values.append("job_ids[]", job.job_id));
  try {
    const response = await fetch("/api/jobs/delete", {
      method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8" }, body: values
    });
    if (!response.ok) throw new Error(await responseError(response, "複数削除に失敗しました"));
    const payload = await response.json();
    payload.deleted.forEach((entry) => selectedJobIds.delete(entry.job_id));
    historyNotice = payload.errors.length
      ? `${payload.deleted.length}件削除、未削除: ${payload.errors.map((entry) => `${entry.job_id}（${entry.error}）`).join("、")}`
      : `${payload.deleted.length}件を削除しました`;
    if (payload.deleted.some((entry) => entry.job_id === currentJobId)) {
      currentJobId = undefined;
      displayedJob = undefined;
      workspace.classList.remove("has-job");
      document.querySelector("#job-panel").hidden = true;
      updateGlobalJob();
      window.history.pushState({ view: "jobs" }, "", "/?view=jobs");
    }
    if (payload.deleted.some((entry) => entry.job_id === activeJobId || entry.job_id === activeJob?.job_id)) {
      activeJobId = undefined;
      activeJob = undefined;
      updateGlobalJob();
    }
    await refreshHistory();
  } catch (error) { showFormError(error.message); }
});

function compareArtifact(job, name) {
  return job?.artifacts?.find((artifact) => artifact.name === name);
}

function renderComparedImages() {
  const kind = document.querySelector("#job-compare-kind").value;
  comparedJobs.forEach((job, index) => {
    const side = index === 0 ? "a" : "b";
    const image = document.querySelector(`#compare-${side}-image`);
    const missing = document.querySelector(`#compare-${side}-missing`);
    const artifact = compareArtifact(job, kind);
    image.hidden = !artifact;
    missing.hidden = Boolean(artifact);
    image.onerror = () => {
      image.hidden = true;
      missing.hidden = false;
    };
    if (artifact) image.src = `${artifact.url}?compare=${encodeURIComponent(job.job_id)}`;
    else image.removeAttribute("src");
  });
  resetViewer("job-compare-preview");
}

function renderJobComparison() {
  const kinds = new Set();
  comparedJobs.forEach((job) => job?.artifacts?.forEach((artifact) => {
    if (previewLabels[artifact.name]) kinds.add(artifact.name);
  }));
  const kindSelect = document.querySelector("#job-compare-kind");
  kindSelect.replaceChildren();
  previewKinds.filter(({ name }) => kinds.has(name)).forEach(({ name, label }) => {
    const availability = comparedJobs.map((job) => Boolean(compareArtifact(job, name)));
    const suffix = availability.every(Boolean) ? "" : `（${availability[0] ? "Aのみ" : "Bのみ"}）`;
    kindSelect.add(new Option(`${label}${suffix}`, name));
  });
  comparedJobs.forEach((job, index) => {
    const side = index === 0 ? "a" : "b";
    document.querySelector(`#compare-${side}-name`).textContent = job
      ? (job.input_name || "入力名の記録なし") : "削除されたジョブ";
    document.querySelector(`#compare-${side}-meta`).textContent = job
      ? `${job.job_id} · ${job.created_at ? new Date(job.created_at).toLocaleString("ja-JP") : "日時なし"} · ${job.width || "—"} × ${job.height || "—"} mm`
      : "取得できません";
    document.querySelector(`#compare-${side}-use`).disabled = !job;
    const preview = document.querySelector(`#compare-${side}-preview`);
    if (job?.width && job?.height) preview.style.aspectRatio = `${job.width} / ${job.height}`;
  });
  const differences = document.querySelector("#job-compare-differences");
  differences.replaceChildren();
  Object.entries(settingLabels).forEach(([key, label]) => {
    const left = comparedJobs[0]?.[key];
    const right = comparedJobs[1]?.[key];
    const normalizedLeft = typeof left === "boolean" ? (left ? "有効" : "無効") : String(left ?? "自動");
    const normalizedRight = typeof right === "boolean" ? (right ? "有効" : "無効") : String(right ?? "自動");
    if (normalizedLeft === normalizedRight) return;
    const row = document.createElement("tr");
    [label, normalizedLeft, normalizedRight].forEach((value) => {
      const cell = document.createElement("td");
      cell.textContent = value;
      row.append(cell);
    });
    differences.append(row);
  });
  if (!differences.childElementCount) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 3;
    cell.textContent = "仕上がりに関係する設定差はありません。";
    row.append(cell);
    differences.append(row);
  }
  const missing = comparedJobs.filter((job) => !job).length;
  const status = document.querySelector("#job-compare-status");
  status.hidden = missing === 0;
  status.textContent = missing ? "比較対象の一方が削除されたため、その側の画像と設定は表示しません。" : "";
  if (kindSelect.options.length) renderComparedImages();
}

document.querySelector("#compare-jobs")?.addEventListener("click", async () => {
  const ids = [...selectedJobIds].filter((id) => historyJobs.get(id)?.state === "completed");
  if (ids.length !== 2) return;
  comparedJobs = await Promise.all(ids.map((id) => fetchJob(id).catch(() => null)));
  renderJobComparison();
  document.querySelector("#job-compare-dialog").showModal();
});
document.querySelector("#job-compare-kind")?.addEventListener("change", renderComparedImages);
document.querySelector("#close-job-compare")?.addEventListener("click", () => document.querySelector("#job-compare-dialog").close());
["a", "b"].forEach((side, index) => {
  document.querySelector(`#compare-${side}-use`)?.addEventListener("click", () => {
    const job = comparedJobs[index];
    if (job && applySettings(job, `ジョブ ${job.job_id} の設定`)) {
      document.querySelector("#job-compare-dialog").close();
      document.querySelector("#conversion-form").scrollIntoView({ block: "start" });
    }
  });
});

async function cancelJob(jobId) {
  if (!jobId) return;
  const detailButton = jobId === currentJobId ? document.querySelector("#cancel-button") : undefined;
  const globalButton = jobId === activeJobId ? document.querySelector("#global-cancel-button") : undefined;
  [detailButton, globalButton].filter(Boolean).forEach((button) => {
    button.disabled = true;
    button.textContent = "停止要求中…";
  });
  try {
    const response = await fetch(`/jobs/${encodeURIComponent(jobId)}/cancel`, { method: "POST", headers: { "X-CSRF-Token": csrfToken } });
    if (!response.ok) throw new Error(await responseError(response, "停止要求に失敗しました"));
  } catch (error) {
    [detailButton, globalButton].filter(Boolean).forEach((button) => {
      button.disabled = false;
      button.textContent = "停止を再試行";
    });
    if (jobId === currentJobId) document.querySelector("#job-message").textContent = error.message;
    if (jobId === activeJobId) document.querySelector("#global-job-label").textContent = `停止要求に失敗: ${error.message}`;
  }
}
document.querySelector("#cancel-button")?.addEventListener("click", () => {
  cancelJob(currentJobId);
});
document.querySelector("#global-cancel-button")?.addEventListener("click", () => {
  cancelJob(activeJobId || currentJobId);
});
document.querySelector("#global-job-link")?.addEventListener("click", () => {
  workspace.classList.remove("show-job-list");
  const jobId = activeJobId || activeJob?.job_id || currentJobId;
  if (jobId) selectJob(jobId);
  else showAppView("jobs", { push: currentView !== "jobs", focus: true });
});
document.querySelector("#back-to-job-list")?.addEventListener("click", () => {
  workspace.classList.add("show-job-list");
  document.querySelector("#history-query")?.focus({ preventScroll: true });
});
document.querySelector("#delete-button")?.addEventListener("click", () => {
  if (currentJobId) deleteJob(currentJobId, document.querySelector("#delete-button"));
});
document.querySelector("#choose-another-image")?.addEventListener("click", () => {
  showAppView("create", { push: currentView !== "create" });
  filePicker.scrollIntoView({ block: "center" });
  filePicker.focus();
});
document.querySelector("#review-settings")?.addEventListener("click", () => {
  showAppView("create", { push: currentView !== "create" });
  const settings = document.querySelector(".settings-section");
  settings.open = true;
  settings.scrollIntoView({ block: "start" });
  document.querySelector("#width")?.focus();
});
document.querySelector("#retry-status-button")?.addEventListener("click", () => {
  if (!currentJobId) return;
  showConnection("loading", "状態を再取得しています");
  pollJob(currentJobId);
});
window.addEventListener("popstate", () => {
  const parameters = new URL(window.location.href).searchParams;
  const jobId = parameters.get("job");
  const view = requestedView();
  currentJobDetailTab = requestedJobTab();
  showAppView(view, { focus: true });
  if (jobId && jobId !== currentJobId) selectJob(jobId, { push: false });
  else if (jobId) selectJobDetailTab(currentJobDetailTab);
  else if (!jobId) {
    currentJobId = undefined;
    displayedJob = undefined;
    workspace.classList.remove("has-job");
    document.querySelector("#job-panel").hidden = true;
    updateGlobalJob();
  }
});

const viewerStates = new Map();
function viewerState(id) {
  if (!viewerStates.has(id)) viewerStates.set(id, { scale: 1, x: 0, y: 0, actual: false });
  return viewerStates.get(id);
}

function viewerViewports(id) {
  const viewport = document.getElementById(id);
  const grouped = [...document.querySelectorAll(`[data-viewer-group="${id}"]`)]
    .filter((candidate) => !candidate.closest("figure")?.hidden);
  return [...new Set([...(viewport ? [viewport] : []), ...grouped])];
}

function viewerImages(id) {
  return viewerViewports(id).flatMap((viewport) => [...viewport.querySelectorAll("img")]);
}

function viewerPanBounds(id) {
  const viewport = viewerViewports(id)[0];
  const state = viewerState(id);
  const image = viewport?.querySelector("img:not(.tile-overlay)");
  if (!viewport || !image) return { x: 0, y: 0 };
  const width = state.actual ? image.naturalWidth : viewport.clientWidth;
  const height = state.actual ? image.naturalHeight : viewport.clientHeight;
  return {
    x: Math.max(0, ((width * state.scale) - viewport.clientWidth) / 2),
    y: Math.max(0, ((height * state.scale) - viewport.clientHeight) / 2)
  };
}

function constrainViewerPan(id) {
  const state = viewerState(id);
  const bounds = viewerPanBounds(id);
  state.x = Math.max(-bounds.x, Math.min(bounds.x, state.x));
  state.y = Math.max(-bounds.y, Math.min(bounds.y, state.y));
  const pannable = bounds.x > 0 || bounds.y > 0;
  viewerViewports(id).forEach((viewport) => viewport.classList.toggle("is-pannable", pannable));
  const hint = document.querySelector(`[data-view-hint="${id}"]`);
  if (hint) hint.textContent = pannable
    ? "ドラッグまたは矢印キーで表示位置を移動できます。"
    : "拡大すると表示位置を移動できます。";
}

function applyViewer(id) {
  const state = viewerState(id);
  constrainViewerPan(id);
  const images = viewerImages(id);
  const reference = images.find((image) => !image.classList.contains("tile-overlay"));
  images.forEach((image) => {
    const naturalWidth = image.classList.contains("tile-overlay") ? reference?.naturalWidth : image.naturalWidth;
    const naturalHeight = image.classList.contains("tile-overlay") ? reference?.naturalHeight : image.naturalHeight;
    image.style.width = state.actual ? `${naturalWidth}px` : "100%";
    image.style.height = state.actual ? `${naturalHeight}px` : "100%";
    image.style.transform = `translate(${state.x}px, ${state.y}px) scale(${state.scale})`;
  });
  const scale = document.querySelector(`[data-viewer="${id}"] [data-view-scale]`);
  if (scale) scale.textContent = state.actual ? "100%" : (state.scale !== 1 ? `${Math.round(state.scale * 100)}%` : "全体");
}

function resetViewer(id) {
  viewerStates.set(id, { scale: 1, x: 0, y: 0, actual: false });
  applyViewer(id);
}

document.querySelectorAll(".preview-toolbar").forEach((toolbar) => {
  const id = toolbar.dataset.viewer;
  toolbar.addEventListener("click", (event) => {
    const action = event.target.dataset.viewAction;
    if (!action) return;
    const state = viewerState(id);
    if (action === "in") state.scale = Math.min(4, state.scale + 0.25);
    if (action === "out") state.scale = Math.max(0.5, state.scale - 0.25);
    if (action === "actual") Object.assign(state, { scale: 1, x: 0, y: 0, actual: true });
    if (action === "reset") resetViewer(id);
    else applyViewer(id);
  });
  toolbar.querySelector("[data-view-background]")?.addEventListener("change", (event) => {
    viewerViewports(id).forEach((viewport) => { viewport.dataset.background = event.target.value; });
  });
});

document.querySelectorAll(".preview-viewport").forEach((viewport) => {
  let drag;
  viewport.addEventListener("pointerdown", (event) => {
    const viewerId = viewport.dataset.viewerGroup || viewport.id;
    const bounds = viewerPanBounds(viewerId);
    if ((!bounds.x && !bounds.y) || (event.pointerType === "mouse" && event.button !== 0)) return;
    event.preventDefault();
    drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
    viewport.setPointerCapture(event.pointerId);
    viewport.classList.add("is-panning");
  });
  viewport.addEventListener("pointermove", (event) => {
    if (!drag || drag.pointerId !== event.pointerId) return;
    event.preventDefault();
    const viewerId = viewport.dataset.viewerGroup || viewport.id;
    const state = viewerState(viewerId);
    state.x += event.clientX - drag.x;
    state.y += event.clientY - drag.y;
    drag = { pointerId: event.pointerId, x: event.clientX, y: event.clientY };
    applyViewer(viewerId);
  });
  const stop = (event) => {
    if (drag && event.pointerId !== drag.pointerId) return;
    drag = undefined;
    viewport.classList.remove("is-panning");
  };
  viewport.addEventListener("pointerup", stop);
  viewport.addEventListener("pointercancel", stop);
  viewport.addEventListener("lostpointercapture", stop);
});
document.querySelectorAll(".preview-viewport img, #compare-source-image").forEach((image) => {
  image.addEventListener("load", () => {
    const viewport = image.closest(".preview-viewport");
    applyViewer(viewport?.dataset.viewerGroup || viewport?.id || "result-preview");
  });
});
window.addEventListener("resize", () => viewerStates.forEach((_state, id) => applyViewer(id)));

function openPreviewDialog(viewerId, trigger) {
  const dialog = document.querySelector("#preview-dialog");
  const sourceFigure = document.querySelector("#dialog-source-figure");
  const resultFigure = document.querySelector("#dialog-result-figure");
  const dialogSource = document.querySelector("#dialog-source-image");
  const dialogResult = document.querySelector("#dialog-result-image");
  const legend = document.querySelector("#dialog-legend");
  dialogReturnFocus = trigger;
  if (viewerId === "source-preview") {
    document.querySelector("#preview-dialog-title").textContent = "編集中の入力を大きく表示";
    sourceFigure.hidden = false;
    resultFigure.hidden = true;
    document.querySelector("#dialog-preview-grid").classList.add("is-single");
    dialogSource.src = sourceImage.src;
    document.querySelector("#dialog-source-caption").textContent = fileInput.files?.[0]?.name || "編集中の入力";
    document.querySelector("#dialog-source-preview").style.aspectRatio = document.querySelector("#source-preview").style.aspectRatio;
    legend.hidden = true;
  } else {
    document.querySelector("#preview-dialog-title").textContent = "変換結果を大きく比較";
    sourceFigure.hidden = !compareSourceImage.getAttribute("src");
    resultFigure.hidden = false;
    document.querySelector("#dialog-preview-grid").classList.toggle("is-single", sourceFigure.hidden);
    dialogSource.src = compareSourceImage.src;
    dialogResult.src = document.querySelector("#result-image").src;
    document.querySelector("#dialog-source-caption").textContent = "変換時の補正後入力";
    document.querySelector("#dialog-result-caption").textContent = document.querySelector("#result-caption").textContent;
    const ratio = document.querySelector("#result-preview").style.aspectRatio;
    document.querySelector("#dialog-source-preview").style.aspectRatio = ratio;
    document.querySelector("#dialog-result-preview").style.aspectRatio = ratio;
    legend.textContent = document.querySelector("#result-legend").textContent;
    legend.hidden = false;
  }
  dialog.showModal();
  window.requestAnimationFrame(() => resetViewer("dialog-preview"));
}

document.querySelectorAll("[data-expand-viewer]").forEach((button) => {
  button.addEventListener("click", () => openPreviewDialog(button.dataset.expandViewer, button));
});
document.querySelector("#close-preview-dialog")?.addEventListener("click", () => document.querySelector("#preview-dialog").close());
document.querySelector("#preview-dialog")?.addEventListener("close", () => dialogReturnFocus?.focus());
document.querySelector("#preview-dialog")?.addEventListener("click", (event) => {
  if (event.target === event.currentTarget) event.currentTarget.close();
});
document.querySelector("#preview-dialog")?.addEventListener("keydown", (event) => {
  if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "+", "-", "0"].includes(event.key)) return;
  if (["INPUT", "SELECT"].includes(event.target.tagName)) return;
  event.preventDefault();
  const state = viewerState("dialog-preview");
  if (event.key === "ArrowLeft") state.x -= 30;
  if (event.key === "ArrowRight") state.x += 30;
  if (event.key === "ArrowUp") state.y -= 30;
  if (event.key === "ArrowDown") state.y += 30;
  if (event.key === "+") state.scale = Math.min(4, state.scale + 0.25);
  if (event.key === "-") state.scale = Math.max(0.5, state.scale - 0.25);
  if (event.key === "0") return resetViewer("dialog-preview");
  applyViewer("dialog-preview");
});

showAppView(currentView);
if (currentJobId) {
  workspace.classList.add("has-job");
  selectJob(currentJobId, { push: false, navigate: currentView === "jobs" });
}
loadSettingsLibrary();
refreshHistory();
window.setInterval(() => {
  if (historyJobs.size <= historyPageSize) refreshHistory();
}, 4000);

window.addEventListener("beforeunload", () => {
  if (previewId) {
    navigator.sendBeacon(`/api/previews/${encodeURIComponent(previewId)}/discard`, new URLSearchParams({ csrf_token: csrfToken }));
  }
  if (sourceUrl) URL.revokeObjectURL(sourceUrl);
  if (tileOverlayUrl) URL.revokeObjectURL(tileOverlayUrl);
});

const { test, expect } = require("@playwright/test");
const path = require("path");
const fs = require("fs");

const example = path.resolve(__dirname, "../../examples/cmy-color-circle.svg");
const visualExamples = ["cmy-color-chart.svg", "cmy-color-circle.svg", "cmy-fine-line.svg"]
  .map((name) => ({ name, path: path.resolve(__dirname, `../../examples/${name}`) }));
const browserLogs = new WeakMap();
const rasterFiles = {
  png: {
    name: "sample.png",
    mimeType: "image/png",
    buffer: Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAtGVYSWZJSSoACAAAAAYAEgEDAAEAAAABAAAAGgEFAAEAAABWAAAAGwEFAAEAAABeAAAAKAEDAAEAAAACAAAAEwIDAAEAAAABAAAAaYcEAAEAAABmAAAAAAAAADhjAADoAwAAOGMAAOgDAAAGAACQBwAEAAAAMDIxMAGRBwAEAAAAAQIDAACgBwAEAAAAMDEwMAGgAwABAAAA//8AAAKgBAABAAAABAAAAAOgBAABAAAAAwAAAAAAAABA7p1OAAAACXBIWXMAAAPoAAAD6AG1e1JrAAAAEElEQVQImWPgqngGRww4OQA+9hDh6XmBGwAAAABJRU5ErkJggg==", "base64")
  },
  jpeg: {
    name: "sample.jpeg",
    mimeType: "image/jpeg",
    buffer: Buffer.from("/9j/4QC8RXhpZgAASUkqAAgAAAAGABIBAwABAAAAAQAAABoBBQABAAAAVgAAABsBBQABAAAAXgAAACgBAwABAAAAAgAAABMCAwABAAAAAQAAAGmHBAABAAAAZgAAAAAAAAA4YwAA6AMAADhjAADoAwAABgAAkAcABAAAADAyMTABkQcABAAAAAECAwAAoAcABAAAADAxMDABoAMAAQAAAP//AAACoAQAAQAAAAQAAAADoAQAAQAAAAMAAAAAAAAA/9sAQwADAgIDAgIDAwMDBAMDBAUIBQUEBAUKBwcGCAwKDAwLCgsLDQ4SEA0OEQ4LCxAWEBETFBUVFQwPFxgWFBgSFBUU/9sAQwEDBAQFBAUJBQUJFA0LDRQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQU/8AAEQgAAwAEAwERAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/aAAwDAQACEQMRAD8A80r+xT+VD//Z", "base64")
  }
};

async function startJob(page, file) {
  await page.locator("#image-input").setInputFiles(file);
  await expect(page.locator("#source-image")).toBeVisible();
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await page.locator("#submit-button").click();
  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
}

async function openView(page, view) {
  const menu = page.locator("#menu-toggle");
  if (await menu.isVisible()) await menu.click();
  await page.locator(`#primary-navigation [data-view-target="${view}"]`).click();
  await expect(page.locator(`[data-app-view="${view}"]`)).toBeVisible();
}

test.beforeEach(async ({ page }) => {
  const entries = [];
  browserLogs.set(page, entries);
  page.on("console", (message) => entries.push(`console.${message.type()}: ${message.text()}`));
  page.on("pageerror", (error) => entries.push(`pageerror: ${error.stack || error.message}`));
  page.on("requestfailed", (request) => entries.push(`requestfailed: ${request.method()} ${request.url()} ${request.failure()?.errorText}`));
});

test.afterEach(async ({ page }, testInfo) => {
  if (testInfo.status === testInfo.expectedStatus) return;
  await testInfo.attach("browser.log", { body: `${browserLogs.get(page).join("\n")}\n`, contentType: "text/plain" });
  const serverLog = path.resolve(__dirname, "../../tmp/playwright-server.log");
  if (fs.existsSync(serverLog)) await testInfo.attach("server.log", { path: serverLog, contentType: "text/plain" });
});

test("keeps the selected image and settings while creating and reviewing a job", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();
  await expect(page.locator("#draft-state")).toContainText("反映済み");

  await page.locator("#brightness").fill("12");
  await page.locator("#submit-button").click();

  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
  await expect(page.locator("#job-panel")).toBeVisible();
  await expect(page.locator("#job-state")).toHaveText("完了");
  await expect(page.locator("#result-image")).toBeVisible();
  await expect(page.locator("#result-tabs button")).toHaveText([
    "CMYW", "Cyan", "Magenta", "Yellow", "White", "透過明度", "厚み"
  ]);
  await page.getByRole("tab", { name: "成果物", exact: true }).click();
  await expect(page.locator('#artifact-list a[href$="lithop.3mf"]')).toBeVisible();
  await page.getByRole("tab", { name: "プレビュー", exact: true }).click();
  await expect(page.locator("#image-input")).toHaveValue(/cmy-color-circle\.svg$/);
  await expect(page.locator("#brightness")).toHaveValue("12");

  await page.getByRole("tab", { name: "厚み" }).click();
  await expect(page.locator("#result-caption")).toHaveText("厚み");
  await page.locator('[data-viewer="result-preview"] [data-view-action="actual"]').click();
  await expect(page.locator('[data-viewer="result-preview"] [data-view-scale]')).toHaveText("100%");
  await page.locator('[data-viewer="result-preview"] [data-view-action="reset"]').click();
  await expect(page.locator('[data-viewer="result-preview"] [data-view-scale]')).toHaveText("全体");
  await page.locator('[data-viewer="result-preview"] [data-view-action="in"]').click({ clickCount: 4 });
  await expect(page.locator('[data-viewer="result-preview"] [data-view-scale]')).toHaveText("200%");
});

test("waits for preview staging before the asynchronous job request", async ({ page }) => {
  await page.route("**/api/previews", async (route) => {
    await new Promise((resolve) => setTimeout(resolve, 300));
    await route.continue();
  });
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await page.locator("#submit-button").click();

  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
  await expect(page.locator("#job-id")).toContainText("browser-job-");
  await expect(page.locator("#form-error")).toBeHidden();
  await expect(page.locator("#job-state")).toHaveText("完了");
});

for (const [format, file] of Object.entries(rasterFiles)) {
  test(`previews and submits ${format.toUpperCase()} input`, async ({ page }) => {
    await page.goto("/");
    await startJob(page, file);
    await expect(page.locator("#job-state")).toHaveText("完了");
    await expect(page.locator("#result-image")).toBeVisible();
    await expect(page.locator("#image-input")).toHaveValue(new RegExp(`${file.name}$`));
  });
}

test("measures normalized JPEG, PNG, and SVG preview response targets", async ({ page }, testInfo) => {
  await page.goto("/");
  const measurements = {};
  for (const [name, file, limit] of [
    ["jpeg", rasterFiles.jpeg, 1000],
    ["png", rasterFiles.png, 1000],
    ["svg", example, 2000]
  ]) {
    const started = Date.now();
    await page.locator("#image-input").setInputFiles(file);
    await expect(page.locator("#draft-state")).toContainText("反映済み");
    measurements[name] = Date.now() - started;
    expect(measurements[name]).toBeLessThan(limit);
  }
  await testInfo.attach("preview-timings.json", {
    body: JSON.stringify({ browser: testInfo.project.name, milliseconds: measurements }, null, 2),
    contentType: "application/json"
  });
});

test("shows common tile boundaries and dependent Z settings", async ({ page }) => {
  await page.goto("/");
  await page.locator("details").filter({ hasText: "XYタイルとZプレート" }).locator("summary").click();
  await page.locator('input[name="tile_count"]').fill("2");
  await page.locator("#toggle-tile-overlay").check();
  await expect(page.locator("#tile-overlay")).toBeVisible();
  await expect(page.locator("#draft-summary-values")).toContainText("1行 × 2列");

  await expect(page.locator("#color-region-field")).toBeHidden();
  await page.locator("#separate-z-parts").check();
  await expect(page.locator("#color-region-field")).toBeVisible();
  await expect(page.locator("#z-parts-summary")).toContainText("Top White 1プレート");
  await expect(page.locator("#draft-summary-values")).toContainText("4プレート");
});

test("shows every split 3MF and its tile preview", async ({ page }) => {
  await page.goto("/");
  await page.locator("details").filter({ hasText: "XYタイルとZプレート" }).locator("summary").click();
  await page.locator('input[name="tile_count"]').fill("2");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  await page.getByRole("tab", { name: "成果物", exact: true }).click();

  const cards = page.locator("#tile-result-list .tile-result-card");
  await expect(cards).toHaveCount(2);
  await expect(cards.locator("img")).toHaveCount(2);
  await expect(cards.getByRole("link", { name: "3MFを保存" })).toHaveCount(2);
  await expect(page.locator('#artifact-list a[href*="tiles/"][href$=".3mf"]')).toHaveCount(2);
});

test("pans enlarged input and result previews by dragging", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();

  const sourceToolbar = page.locator('[data-viewer="source-preview"]');
  await sourceToolbar.locator('[data-view-action="in"]').click({ clickCount: 2 });
  await expect(page.locator("#source-preview")).toHaveClass(/is-pannable/);
  const sourceBox = await page.locator("#source-preview").boundingBox();
  await page.mouse.move(sourceBox.x + (sourceBox.width / 2), sourceBox.y + (sourceBox.height / 2));
  await page.mouse.down();
  await page.mouse.move(sourceBox.x + (sourceBox.width / 2) + 40, sourceBox.y + (sourceBox.height / 2) + 30);
  await page.mouse.up();
  await expect(page.locator("#source-image")).toHaveCSS("transform", /matrix\(1\.5, 0, 0, 1\.5, 40, 30\)/);
  await sourceToolbar.locator('[data-view-action="reset"]').click();
  await expect(page.locator("#source-preview")).not.toHaveClass(/is-pannable/);
  await sourceToolbar.locator('[data-view-action="actual"]').click();
  await expect(page.locator("#source-preview")).toHaveClass(/is-pannable/);
  await page.mouse.move(sourceBox.x + (sourceBox.width / 2), sourceBox.y + (sourceBox.height / 2));
  await page.mouse.down();
  await page.mouse.move(sourceBox.x + (sourceBox.width / 2) - 20, sourceBox.y + (sourceBox.height / 2) - 15);
  await page.mouse.up();
  await expect(page.locator("#source-image")).toHaveCSS("transform", /matrix\(1, 0, 0, 1, -20, -15\)/);
  await sourceToolbar.locator('[data-view-action="reset"]').click();

  await page.locator("#submit-button").click();
  await expect(page.locator("#job-state")).toHaveText("完了");
  const resultToolbar = page.locator('[data-viewer="result-preview"]');
  await resultToolbar.locator('[data-view-action="in"]').click({ clickCount: 2 });
  const resultPreview = page.locator("#result-preview");
  await resultPreview.scrollIntoViewIfNeeded();
  const resultBox = await resultPreview.boundingBox();
  await page.mouse.move(resultBox.x + (resultBox.width / 2), resultBox.y + (resultBox.height / 2));
  await page.mouse.down();
  await page.mouse.move(resultBox.x + (resultBox.width / 2) - 35, resultBox.y + (resultBox.height / 2) - 25);
  await page.mouse.up();
  await expect(page.locator("#result-image")).toHaveCSS("transform", /matrix\(1\.5, 0, 0, 1\.5, -35, -25\)/);
  await expect(page.locator("#compare-source-image")).toHaveCSS("transform", /matrix\(1\.5, 0, 0, 1\.5, -35, -25\)/);
});

test("gives portrait corrected input enough height to show the complete image", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");
  await page.locator("#aspect-lock").uncheck();
  await page.locator("#width").fill("104");
  await page.locator("#height").fill("140");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");

  const dimensions = await page.evaluate(() => {
    const corrected = document.querySelector(".comparison-source").getBoundingClientRect();
    const generated = document.querySelector("#result-preview").getBoundingClientRect();
    return {
      corrected: { width: corrected.width, height: corrected.height },
      generated: { width: generated.width, height: generated.height },
      imageFit: getComputedStyle(document.querySelector("#compare-source-image")).objectFit
    };
  });
  expect(dimensions.corrected.height).toBeGreaterThan(dimensions.corrected.width);
  expect(dimensions.corrected.width / dimensions.corrected.height).toBeCloseTo(104 / 140, 2);
  expect(dimensions.generated).toEqual(dimensions.corrected);
  expect(dimensions.imageFit).toBe("contain");
});

test("restores the corrected input when a recent job is selected", async ({ page }) => {
  await page.goto("/");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  const jobId = await page.locator("#job-id").textContent();

  await page.goto("/");
  await openView(page, "jobs");
  const recentJob = page.locator(`#job-list a[data-job-id="${jobId}"]`);
  await expect(recentJob).toBeVisible();
  await recentJob.click();
  await expect(page.locator("#job-state")).toHaveText("完了");
  await expect(page.locator("#corrected-input-figure")).toBeVisible();
  await expect(page.locator("#compare-source-image")).toHaveAttribute(
    "src", new RegExp(`/jobs/${jobId}/files/corrected-input\\.png`)
  );
  await expect(page.locator("#compare-source-image")).toBeVisible();

  const persistedSource = await page.locator("#compare-source-image").getAttribute("src");
  await page.locator("#image-input").setInputFiles(rasterFiles.png);
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await expect(page.locator("#compare-source-image")).toHaveAttribute("src", persistedSource);
  await expect(page.locator("#job-settings-snapshot")).toContainText("編集中と異なる項目");
  await expect(page.locator("#draft-summary-change")).toContainText("項目を編集中");
});

test("opens large input and result previews and restores focus when closed", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();

  const inputExpand = page.getByRole("button", { name: "大きく表示" });
  await inputExpand.click();
  await expect(page.locator("#preview-dialog")).toBeVisible();
  await expect(page.locator("#dialog-source-figure")).toBeVisible();
  await expect(page.locator("#dialog-result-figure")).toBeHidden();
  await page.locator('[data-viewer="dialog-preview"] [data-view-action="in"]').click();
  await expect(page.locator('[data-viewer="dialog-preview"] [data-view-scale]')).toHaveText("125%");
  await page.locator("#close-preview-dialog").click();
  await expect(inputExpand).toBeFocused();

  await page.locator("#submit-button").click();
  await expect(page.locator("#job-state")).toHaveText("完了");
  await page.getByRole("button", { name: "大きく比較" }).click();
  await expect(page.locator("#dialog-source-figure")).toBeVisible();
  await expect(page.locator("#dialog-result-figure")).toBeVisible();
  await page.locator("#preview-dialog").press("Escape");
  await expect(page.locator("#preview-dialog")).toBeHidden();
});

test("links the tile overview to every model and shows its physical placement", async ({ page }) => {
  await page.goto("/");
  await page.locator("details").filter({ hasText: "XYタイルとZプレート" }).locator("summary").click();
  await page.locator('input[name="tile_count"]').fill("3");
  await page.locator("#separate-z-parts").check();
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  await expect(page.locator("#result-tabs button")).toHaveText([
    "CMYW", "Cyan", "Magenta", "Yellow", "White", "透過明度", "厚み", "タイル"
  ]);
  await page.getByRole("tab", { name: "成果物", exact: true }).click();

  const mapTiles = page.locator(".tile-map button");
  await expect(mapTiles).toHaveCount(3);
  await mapTiles.nth(1).click();
  await expect(page.locator("#tile-card-tile_r01_c02")).toHaveClass(/is-selected/);
  await expect(page.locator("#tile-card-tile_r01_c02 > small")).toContainText("行1・列2");
  await expect(page.locator("#tile-card-tile_r01_c02 > small")).toContainText("4プレート");
  await expect(page.locator("#tile-card-tile_r01_c02 a")).toHaveAttribute("href", /tile_r01_c02\.3mf$/);
});

test("distinguishes a temporary status connection failure and recovers without another job", async ({ page }) => {
  let failed = false;
  await page.route("**/api/jobs/browser-job-*", async (route) => {
    if (!failed) {
      failed = true;
      await route.abort();
    } else {
      await route.continue();
    }
  });
  await page.goto("/");
  const before = await page.request.get("/api/jobs?limit=50").then((response) => response.json());
  await page.locator("#image-input").setInputFiles(example);
  await page.locator("#submit-button").click();
  await expect(page.locator("#job-connection")).toContainText("通信できません");
  await expect(page.locator("#retry-status-button")).toBeVisible();
  await page.locator("#retry-status-button").click();
  await expect(page.locator("#job-state")).toHaveText("完了");
  const after = await page.request.get("/api/jobs?limit=50").then((response) => response.json());
  expect(after.total).toBe(before.total + 1);
});

test("stops and deletes a job without leaving the editing form", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();
  await page.locator("#submit-button").click();
  await expect(page.locator("#cancel-button")).toBeVisible();
  await page.locator("#cancel-button").click();
  await expect(page.locator("#job-state")).toHaveText("停止済み");

  page.once("dialog", (dialog) => dialog.accept());
  await page.locator("#delete-button").click();
  await expect(page.locator("#job-panel")).toBeHidden();
  await expect(page.locator("#image-input")).toHaveValue(/cmy-color-circle\.svg$/);
});

test("reports a failed job and permits a retry", async ({ page }) => {
  const failure = {
    name: "failure.svg", mimeType: "image/svg+xml",
    buffer: Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2 1"><rect width="2" height="1" fill="#EC008C"/></svg>')
  };
  await page.goto("/");
  await startJob(page, failure);
  await expect(page.locator("#job-state")).toHaveText("失敗");
  await expect(page.locator("#job-error")).toContainText("Browser fixture conversion failed");
  await expect(page.locator("#job-log-link")).toBeVisible();
  await expect(page.locator("#job-log-link")).toHaveAttribute("href", /\/jobs\/browser-job-\d+\/log$/);
  await page.locator("#review-settings").click();
  await expect(page.locator("#width")).toBeFocused();
  await openView(page, "jobs");
  await page.locator("#choose-another-image").click();
  await expect(page.locator("#file-picker")).toBeFocused();

  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await page.locator("#submit-button").click();
  await expect(page.locator("#job-state")).toHaveText("完了");
});

test("prevents duplicate submission and reflects a stop from another tab", async ({ page, context }) => {
  await page.goto("/");
  const before = await page.request.get("/api/jobs?limit=50").then((response) => response.json());
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();
  await page.locator("#submit-button").dblclick();
  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
  const jobId = new URL(page.url()).searchParams.get("job");
  const after = await page.request.get("/api/jobs?limit=50").then((response) => response.json());
  expect(after.total).toBe(before.total + 1);

  const secondPage = await context.newPage();
  await secondPage.goto(`/?job=${jobId}`);
  await expect(secondPage.locator("#cancel-button")).toBeVisible();
  await secondPage.locator("#cancel-button").click();
  await expect(secondPage.locator("#job-state")).toHaveText("停止済み");
  await expect(page.locator("#job-state")).toHaveText("停止済み");
});

test("shows invalid input errors without keeping an obsolete preview", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles({
    name: "broken.svg", mimeType: "image/svg+xml", buffer: Buffer.from("<svg><broken")
  });
  await expect(page.locator("#source-placeholder")).toContainText("読み込み失敗");

  await page.locator("#image-input").setInputFiles(rasterFiles.png);
  await expect(page.locator("#source-image")).toBeVisible();
  await expect(page.locator("#form-error")).toBeHidden();
});

test("keeps the newest image when selections and renders overlap", async ({ page }) => {
  let delayed = false;
  await page.route("**/api/previews/*/render", async (route) => {
    if (!delayed) {
      delayed = true;
      await new Promise((resolve) => setTimeout(resolve, 400));
    }
    await route.continue();
  });
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await page.locator("#image-input").setInputFiles(rasterFiles.png);
  await expect(page.locator("#file-name")).toHaveText("sample.png");
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await page.waitForTimeout(500);
  await expect(page.locator("#file-name")).toHaveText("sample.png");
  await expect(page.locator("#source-image")).toBeVisible();
});

test("renders the bundled chart, circle, and fine-line SVGs", async ({ page }, testInfo) => {
  await page.goto("/");
  for (const fixture of visualExamples) {
    await page.locator("#image-input").setInputFiles(fixture.path);
    await expect(page.locator("#draft-state")).toContainText("反映済み");
    await expect(page.locator("#source-image")).toBeVisible();
    expect(await page.locator("#source-image").evaluate((image) => image.naturalWidth > 0 && image.naturalHeight > 0)).toBe(true);
    await page.locator("#source-preview").screenshot({
      path: path.resolve(__dirname, `../../tmp/ui06-${testInfo.project.name}-${fixture.name}.png`)
    });
  }
});

test("keeps the input preview from covering recent jobs", async ({ page }) => {
  await page.goto("/");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  await page.goto("/");
  await openView(page, "jobs");
  const history = page.locator(".history-panel");
  await history.scrollIntoViewIfNeeded();
  await expect(history).toBeVisible();

  const overlap = await page.evaluate(() => {
    const preview = document.querySelector(".preview-panel").getBoundingClientRect();
    const recent = document.querySelector(".history-panel").getBoundingClientRect();
    const width = Math.max(0, Math.min(preview.right, recent.right) - Math.max(preview.left, recent.left));
    const height = Math.max(0, Math.min(preview.bottom, recent.bottom) - Math.max(preview.top, recent.top));
    return width * height;
  });
  expect(overlap).toBe(0);
  await page.locator("#history-filter").selectOption("completed");
  await expect(page.locator("#job-list li[data-state='completed']")).not.toHaveCount(0);
});

test("uses a 1440 by 900 viewport as the minimum two-column layout", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto("/");
  const desktopLayout = await page.evaluate(() => {
    const editor = document.querySelector(".editor-panel").getBoundingClientRect();
    const preview = document.querySelector(".preview-panel").getBoundingClientRect();
    return {
      sameRow: Math.abs(editor.top - preview.top) < 1,
      editorBeforePreview: editor.right <= preview.left,
      pageFits: document.documentElement.scrollWidth <= window.innerWidth
    };
  });
  expect(desktopLayout).toEqual({ sameRow: true, editorBeforePreview: true, pageFits: true });

  await page.setViewportSize({ width: 1439, height: 900 });
  const compactLayout = await page.evaluate(() => {
    const editor = document.querySelector(".editor-panel").getBoundingClientRect();
    const preview = document.querySelector(".preview-panel").getBoundingClientRect();
    return {
      sameRow: Math.abs(editor.top - preview.top) < 1,
      editorBeforePreview: editor.right <= preview.left,
      menuCollapsed: getComputedStyle(document.querySelector("#menu-toggle")).display !== "none",
      pageFits: document.documentElement.scrollWidth <= window.innerWidth
    };
  });
  expect(compactLayout).toEqual({ sameRow: true, editorBeforePreview: true, menuCollapsed: true, pageFits: true });
});

test("supports a narrow keyboard workflow without external requests", async ({ page }) => {
  const externalRequests = [];
  page.on("request", (request) => {
    const url = new URL(request.url());
    if (["http:", "https:"].includes(url.protocol) && url.hostname !== "127.0.0.1") {
      externalRequests.push(request.url());
    }
  });
  await page.setViewportSize({ width: 600, height: 800 });
  await page.goto("/");
  await page.locator("#menu-toggle").focus();
  await expect(page.locator("#menu-toggle")).toBeFocused();
  await page.locator("#menu-toggle").press("Enter");
  await expect(page.locator("#primary-navigation")).toBeVisible();
  await page.locator("body").press("Escape");
  await expect(page.locator("#menu-toggle")).toBeFocused();
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  await expect(page.locator(".history-panel")).toBeHidden();
  await page.locator("#back-to-job-list").click();
  await expect(page.locator(".history-panel")).toBeVisible();
  await expect(page.locator("#job-panel")).toBeHidden();
  await page.locator("#global-job-link").click();
  await expect(page.locator("#job-panel")).toBeVisible();
  expect(externalRequests).toEqual([]);
  expect(browserLogs.get(page).filter((entry) => entry.includes("Refused to apply a stylesheet"))).toEqual([]);
});

test("saves and restores reusable settings without replacing the selected image", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await page.locator("#width").fill("120");
  await openView(page, "presets");
  await page.locator("#preset-name").fill("fine-line");
  await page.locator("#preset-save").click();
  await expect(page.locator("#settings-library-status")).toContainText("保存しました");
  await openView(page, "create");
  await page.locator("#width").fill("135");
  await openView(page, "presets");
  page.once("dialog", (dialog) => dialog.accept());
  await page.locator("#preset-load").click();
  await expect(page.locator("#width")).toHaveValue("120");
  await expect(page.locator("#file-name")).toHaveText("cmy-color-circle.svg");

  await page.locator("#height").fill("88");
  await openView(page, "presets");
  await page.locator("#draft-save").click();
  await expect(page.locator("#settings-library-status")).toContainText("下書き設定を保存");
  await page.reload();
  page.once("dialog", (dialog) => dialog.accept());
  await page.locator("#draft-restore").click();
  await expect(page.locator("#height")).toHaveValue("88");
  await expect(page.locator("#draft-state")).toContainText("画像を選択してください");
});

test("compares two completed jobs with synchronized preview choices and setting differences", async ({ page }) => {
  await page.goto("/");
  await page.locator("#brightness").fill("0");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  const firstId = new URL(page.url()).searchParams.get("job");
  await openView(page, "create");
  await page.locator("#brightness").fill("15");
  await page.locator("#submit-button").click();
  await expect(page.locator("#job-id")).not.toHaveText(firstId);
  await expect(page.locator("#job-state")).toHaveText("完了");
  const secondId = new URL(page.url()).searchParams.get("job");
  await page.locator(`#job-list .history-select[data-job-id="${firstId}"]`).check();
  await page.locator(`#job-list .history-select[data-job-id="${secondId}"]`).check();
  await page.locator("#compare-jobs").click();

  await expect(page.locator("#job-compare-dialog")).toBeVisible();
  await expect(page.locator("#job-compare-kind option")).toHaveText([
    "CMYW", "Cyan", "Magenta", "Yellow", "White", "透過明度", "厚み"
  ]);
  await expect(page.locator("#compare-a-meta")).toContainText("browser-job-");
  await expect(page.locator("#compare-b-meta")).toContainText("browser-job-");
  await expect(page.locator("#job-compare-differences")).toContainText("明るさ");
  await page.locator("#job-compare-kind").selectOption("thickness.png");
  await expect(page.locator("#compare-a-image")).toBeVisible();
  await expect(page.locator("#compare-b-image")).toBeVisible();
  await page.locator('[data-viewer="job-compare-preview"] [data-view-action="in"]').click();
  await expect(page.locator('[data-viewer="job-compare-preview"] [data-view-scale]')).toHaveText("125%");
  await page.setViewportSize({ width: 720, height: 900 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
  await expect(page.locator("#compare-b-preview")).toBeVisible();
});

test("searches history, downloads a confirmed artifact ZIP, and bulk deletes final jobs", async ({ page }) => {
  await page.goto("/");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");
  const firstId = new URL(page.url()).searchParams.get("job");
  await openView(page, "create");
  await page.locator("#brightness").fill("3");
  await page.locator("#submit-button").click();
  await expect(page.locator("#job-id")).not.toHaveText(firstId);
  await expect(page.locator("#job-state")).toHaveText("完了");
  const secondId = new URL(page.url()).searchParams.get("job");

  await page.getByRole("tab", { name: "成果物", exact: true }).click();
  page.once("dialog", (dialog) => dialog.accept());
  const [download] = await Promise.all([
    page.waitForEvent("download"),
    page.locator("#download-models").click()
  ]);
  expect(download.suggestedFilename()).toContain("models.zip");

  await page.locator("#history-query").fill(firstId);
  await expect(page.locator("#job-list li")).toHaveCount(1);
  await expect(page.locator("#job-list")).toContainText(firstId);
  await page.locator("#history-query").fill("");
  await expect(page.locator(`#job-list .history-select[data-job-id="${firstId}"]`)).toBeVisible();
  await page.locator(`#job-list .history-select[data-job-id="${firstId}"]`).check();
  await page.locator(`#job-list .history-select[data-job-id="${secondId}"]`).check();
  page.once("dialog", (dialog) => dialog.accept());
  await page.locator("#delete-selected-jobs").click();
  await expect(page.locator("#history-selection-status")).toContainText("2件を削除しました");
  const history = await page.request.get("/api/jobs?limit=50").then((response) => response.json());
  expect(history.jobs.map((job) => job.job_id)).not.toContain(firstId);
  expect(history.jobs.map((job) => job.job_id)).not.toContain(secondId);
});

test("pages many jobs and lazily renders a many-tile result", async ({ page }, testInfo) => {
  const seeded = await page.request.get("/__test__/seed-history?count=60&tiles=24");
  expect(seeded.ok()).toBe(true);
  const started = Date.now();
  await page.goto("/");
  await openView(page, "jobs");
  await page.locator("#history-query").fill("seed-history");
  await expect(page.locator("#job-list li")).toHaveCount(12);
  const firstPageMilliseconds = Date.now() - started;
  expect(firstPageMilliseconds).toBeLessThan(5000);
  await expect(page.locator("#load-more-jobs")).toBeVisible();
  await page.locator("#load-more-jobs").click();
  await expect(page.locator("#job-list li")).toHaveCount(24);
  expect(await page.locator("#job-list .history-thumbnail").first().getAttribute("loading")).toBe("lazy");

  await page.locator("#history-query").fill("seed-history-000");
  await expect(page.locator("#job-list li")).toHaveCount(1);
  await expect(page.locator("#job-list")).toContainText("browser-seed-000");

  await page.locator("#history-query").fill("browser-seed-tiles");
  await expect(page.locator("#job-list li")).toHaveCount(1);
  await expect(page.locator("#job-list")).toContainText("browser-seed-tiles");
  await page.locator("#job-list a").click();
  await page.getByRole("tab", { name: "成果物", exact: true }).click();
  await expect(page.locator("#tile-result-list .tile-result-card")).toHaveCount(24);
  expect(await page.locator("#tile-result-list img").first().getAttribute("loading")).toBe("lazy");
  await testInfo.attach("p3-history-performance.json", {
    body: JSON.stringify({ jobs: 60, tiles: 24, firstPageMilliseconds }, null, 2),
    contentType: "application/json"
  });
});

test("navigates panes with browser history while retaining the editing state", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#draft-state")).toContainText("反映済み");
  await page.locator("#width").fill("122");

  await openView(page, "presets");
  await expect(page).toHaveURL(/view=presets/);
  await openView(page, "jobs");
  await page.locator("#history-query").fill("browser-job");
  await expect(page).toHaveURL(/view=jobs/);

  await page.goBack();
  await expect(page.locator("#view-presets")).toBeVisible();
  await page.goBack();
  await expect(page.locator("#view-create")).toBeVisible();
  await expect(page.locator("#width")).toHaveValue("122");
  await expect(page.locator("#image-input")).toHaveValue(/cmy-color-circle\.svg$/);

  await page.goForward();
  await page.goForward();
  await expect(page.locator("#view-jobs")).toBeVisible();
  await expect(page.locator("#history-query")).toHaveValue("browser-job");
});

test("keeps the active job controls while a past job is being viewed", async ({ page }) => {
  await page.goto("/");
  await page.request.get("/__test__/seed-history?count=1&tiles=1");
  await openView(page, "jobs");
  await page.locator("#history-query").fill("seed-history-000");
  await expect(page.locator('#job-list a[data-job-id="browser-seed-000"]')).toBeVisible();
  await openView(page, "create");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();
  await page.locator("#submit-button").click();
  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
  const activeId = new URL(page.url()).searchParams.get("job");
  await expect(page.locator("#global-job-control")).toBeVisible();
  await expect(page.locator("#global-cancel-button")).toBeVisible();

  await page.locator('#job-list a[data-job-id="browser-seed-000"]').click();
  await expect(page.locator("#job-id")).toHaveText("browser-seed-000");
  await expect(page.locator("#global-job-label")).toContainText(activeId);
  await expect(page.locator("#global-cancel-button")).toBeVisible();
  await page.locator("#global-cancel-button").click();
  await page.locator("#global-job-link").click();
  await expect(page.locator("#job-id")).toHaveText(activeId);
  await expect(page.locator("#job-state")).toHaveText("停止済み");
});

test("reports background completion without changing the current pane", async ({ page }) => {
  await page.goto("/");
  await page.locator("#image-input").setInputFiles(example);
  await expect(page.locator("#source-image")).toBeVisible();
  await page.locator("#submit-button").click();
  await expect(page).toHaveURL(/\?job=browser-job-\d+/);
  await openView(page, "presets");
  await expect(page.locator("#global-job-label")).toContainText("完了");
  await expect(page.locator("#view-presets")).toBeVisible();
});

test("switches job detail tabs with the keyboard", async ({ page }) => {
  await page.goto("/");
  await startJob(page, example);
  await expect(page.locator("#job-state")).toHaveText("完了");

  const previewTab = page.getByRole("tab", { name: "プレビュー", exact: true });
  await previewTab.focus();
  await previewTab.press("ArrowRight");
  await expect(page.getByRole("tab", { name: "成果物", exact: true })).toHaveAttribute("aria-selected", "true");
  await expect(page).toHaveURL(/tab=artifacts/);
  await expect(page.locator("#job-artifacts-panel")).toBeVisible();
  await page.getByRole("tab", { name: "成果物", exact: true }).press("ArrowRight");
  await expect(page.locator("#job-settings-panel")).toBeVisible();
  await expect(page).toHaveURL(/tab=settings/);
  await expect(page.locator("#job-setting-details")).toContainText("幅");
  await page.goBack();
  await expect(page.locator("#job-artifacts-panel")).toBeVisible();
  await page.reload();
  await expect(page.locator("#job-artifacts-panel")).toBeVisible();
});

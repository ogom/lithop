const { defineConfig, devices } = require("@playwright/test");
const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const portFile = path.resolve(__dirname, "tmp/playwright-port");
fs.mkdirSync(path.dirname(portFile), { recursive: true });
const port = fs.existsSync(portFile)
  ? Number(fs.readFileSync(portFile, "utf8"))
  : Number(execFileSync(
    "bundle",
    ["exec", "ruby", "-rsocket", "-e", 'server = TCPServer.new("127.0.0.1", 0); puts server.addr[1]; server.close']
  ).toString().trim());
if (!fs.existsSync(portFile)) fs.writeFileSync(portFile, `${port}\n`);

module.exports = defineConfig({
  testDir: "./spec/browser",
  outputDir: "./tmp/playwright-results",
  timeout: 30_000,
  expect: { timeout: 8_000 },
  fullyParallel: false,
  workers: 1,
  reporter: [["list"]],
  globalTeardown: "./spec/browser/support/global_teardown.js",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
    video: "retain-on-failure"
  },
  projects: [
    { name: "chromium", use: { ...devices["Desktop Chrome"] } },
    { name: "webkit", use: { ...devices["Desktop Safari"] } }
  ],
  webServer: {
    command: `LITHOP_BROWSER_PORT=${port} bundle exec ruby spec/browser/support/server.rb`,
    url: `http://127.0.0.1:${port}`,
    reuseExistingServer: false,
    timeout: 30_000,
    stdout: "pipe",
    stderr: "pipe"
  }
});

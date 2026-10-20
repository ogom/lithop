const fs = require("fs");
const path = require("path");

module.exports = async () => {
  fs.rmSync(path.resolve(__dirname, "../../../tmp/playwright-port"), { force: true });
};

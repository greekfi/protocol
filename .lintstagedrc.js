const path = require("path");
const fs = require("fs");

const buildNextEslintCommand = (filenames) => {
  const cwd = path.join(process.cwd(), "core");
  const relativeFiles = filenames
    .map((f) => path.relative(cwd, f))
    .join(" ");
  return `cd core && eslint --fix ${relativeFiles}`;
};

const checkTypesNextCommand = () => "yarn next:check-types";

const buildFoundryFormatCommand = (filenames) => {
  const cwd = path.join(process.cwd(), "foundry");
  // Filter out files that don't exist (might be deleted)
  const existingFiles = filenames.filter((f) => fs.existsSync(f));
  if (existingFiles.length === 0) return "true"; // No-op if no files exist

  const relativeFiles = existingFiles
    .map((f) => path.relative(cwd, f))
    .join(" ");
  return `cd foundry && forge fmt ${relativeFiles}`;
};

module.exports = {
  "core/**/*.{ts,tsx}": [
    buildNextEslintCommand,
    checkTypesNextCommand,
  ],
  "core/**/*.{js,jsx}": [buildNextEslintCommand],
  "foundry/**/*.sol": [buildFoundryFormatCommand],
};

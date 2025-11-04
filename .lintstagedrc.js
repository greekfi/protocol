const path = require("path");
const fs = require("fs");

const buildNextEslintCommand = (filenames) => {
  const cwd = path.join(process.cwd(), "packages", "nextjs");
  const relativeFiles = filenames
    .map((f) => path.relative(cwd, f))
    .join(" ");
  return `cd packages/nextjs && eslint --fix ${relativeFiles}`;
};

const checkTypesNextCommand = () => "yarn next:check-types";

const buildFoundryFormatCommand = (filenames) => {
  const cwd = path.join(process.cwd(), "packages", "foundry");
  // Filter out files that don't exist (might be deleted)
  const existingFiles = filenames.filter((f) => fs.existsSync(f));
  if (existingFiles.length === 0) return "true"; // No-op if no files exist

  const relativeFiles = existingFiles
    .map((f) => path.relative(cwd, f))
    .join(" ");
  return `cd packages/foundry && forge fmt ${relativeFiles}`;
};

module.exports = {
  "packages/nextjs/**/*.{ts,tsx}": [
    buildNextEslintCommand,
    checkTypesNextCommand,
  ],
  "packages/nextjs/**/*.{js,jsx}": [buildNextEslintCommand],
  "packages/foundry/**/*.sol": [buildFoundryFormatCommand],
};

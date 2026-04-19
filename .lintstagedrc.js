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
  // Filter out files that don't exist (might be deleted)
  const existingFiles = filenames.filter((f) => fs.existsSync(f));
  if (existingFiles.length === 0) return "true"; // No-op if no files exist

  // Use absolute paths so lint-staged's post-task re-stage picks up the
  // rewritten content. With `cd foundry && forge fmt <relpath>` the file
  // is rewritten on disk but lint-staged's diff check misses it, so the
  // pre-format content ends up in the commit.
  return `forge fmt ${existingFiles.join(" ")}`;
};

module.exports = {
  "core/**/*.{ts,tsx}": [
    buildNextEslintCommand,
    checkTypesNextCommand,
  ],
  "core/**/*.{js,jsx}": [buildNextEslintCommand],
  "foundry/**/*.sol": [buildFoundryFormatCommand],
};

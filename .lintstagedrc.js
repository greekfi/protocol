const fs = require("fs");

const buildNextEslintCommand = (filenames) => {
  // Hook runs lint-staged from git root with core/node_modules/.bin on
  // PATH (so eslint binary resolves). cd into core/ so eslint finds
  // core/eslint.config.mjs — eslint v9 uses flat config by default and
  // looks in cwd. Files come in as absolute paths from lint-staged.
  return `cd core && eslint --fix ${filenames.join(" ")}`;
};

// tsc needs a tsconfig.json in cwd, so run via core/'s `check-types` script.
const checkTypesNextCommand = () => "yarn --cwd core check-types";

const buildFoundryFormatCommand = (filenames) => {
  // Filter out files that don't exist (might be deleted)
  const existingFiles = filenames.filter((f) => fs.existsSync(f));
  if (existingFiles.length === 0) return "true"; // No-op if no files exist

  // `--root foundry` so forge picks up foundry/foundry.toml (bracket_spacing
  // etc.). Without it, forge defaults to the git-repo root and falls back to
  // its own defaults — producing output that disagrees with CI (which runs
  // `forge fmt` from `working-directory: foundry`). Absolute paths still
  // required so lint-staged's post-task diff sees the rewritten files.
  return `forge fmt --root foundry ${existingFiles.join(" ")}`;
};

module.exports = {
  "core/**/*.{ts,tsx}": [
    buildNextEslintCommand,
    checkTypesNextCommand,
  ],
  "core/**/*.{js,jsx}": [buildNextEslintCommand],
  "foundry/**/*.sol": [buildFoundryFormatCommand],
};

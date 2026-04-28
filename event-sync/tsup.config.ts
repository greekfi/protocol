import { defineConfig } from "tsup";

export default defineConfig({
  entry: ["src/index.ts"],
  format: ["esm"],
  outExtension: () => ({ js: ".mjs" }),
  target: "node20",
  splitting: false,
  sourcemap: true,
  clean: true,
  dts: false,
});

import nextVitals from "eslint-config-next/core-web-vitals";

const config = [
  {
    ignores: [
      // Build outputs
      ".next/**",
      ".next",
      "out/**",
      "out",
      "build/**",
      "build",
      "dist/**",
      "dist",

      // Dependencies
      "node_modules/**",
      "node_modules",

      // Generated files
      "next-env.d.ts",
      "*.tsbuildinfo",
      "**/*.tsbuildinfo",

      // Testing
      "coverage/**",
      "coverage",

      // Cache
      ".cache/**",
      ".cache",
      ".turbo/**",
      ".turbo",

      // Vercel
      ".vercel/**",
      ".vercel",

      // Environment files
      ".env",
      ".env.*",

      // System files
      ".DS_Store",
      "**/.DS_Store",

      // Generated contract ABIs and artifacts
      "contracts/deployments/**",
      "contracts/artifacts/**",
      "contracts/cache/**",
      "app/**/abi/**",
    ],
  },
  ...nextVitals,
];
export default config;

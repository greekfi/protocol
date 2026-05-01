import type { NextConfig } from "next";
import path from "path";

// `~~/*` lives at the repo root (one level above core/) — see tsconfig.json's
// `paths`. Without the old yarn workspace, webpack/Turbopack consider core/
// the project root and silently miss the `../*` branch of the tsconfig path.
// Add it back as an explicit module resolution alias.
const repoRoot = path.resolve(__dirname, "..");

const nextConfig: any = {
  reactStrictMode: true,
  devIndicators: false,
  typescript: {
    ignoreBuildErrors: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  turbopack: {
    resolveAlias: {
      "~~": repoRoot,
    },
  },
  // Output-file tracing follows imports for the standalone build. With
  // imports reaching out to ../abi/, the tracer needs the repo root,
  // not core/, as its boundary.
  outputFileTracingRoot: repoRoot,
  serverExternalPackages: ["pino-pretty", "lokijs", "encoding", "thread-stream"],
  webpack: (config: any) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    config.resolve.alias = {
      ...(config.resolve.alias ?? {}),
      "~~": repoRoot,
    };
    config.externals.push("pino-pretty", "lokijs", "encoding", "thread-stream");
    config.module.rules.push({
      test: /\.test\.(js|ts|jsx|tsx)$/,
      loader: "ignore-loader",
    });
    return config;
  },
};

const isIpfs = process.env.NEXT_PUBLIC_IPFS_BUILD === "true";

if (isIpfs) {
  nextConfig.output = "export";
  nextConfig.trailingSlash = true;
  nextConfig.images = {
    unoptimized: true,
  };
}

export default nextConfig as NextConfig;

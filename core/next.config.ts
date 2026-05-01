import type { NextConfig } from "next";
import path from "path";

// `~~/*` is the legacy Scaffold-ETH alias for the project root. Now that
// abi/ lives under core/, `~~` resolves to core/ itself.
const projectRoot = __dirname;

const nextConfig: any = {
  reactStrictMode: true,
  devIndicators: false,
  typescript: {
    ignoreBuildErrors: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  turbopack: {
    resolveAlias: {
      "~~": projectRoot,
    },
  },
  serverExternalPackages: ["pino-pretty", "lokijs", "encoding", "thread-stream"],
  webpack: (config: any) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
    config.resolve.alias = {
      ...(config.resolve.alias ?? {}),
      "~~": projectRoot,
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

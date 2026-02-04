import type { NextConfig } from "next";

const nextConfig: any = {
  reactStrictMode: true,
  devIndicators: false,
  typescript: {
    ignoreBuildErrors: process.env.NEXT_PUBLIC_IGNORE_BUILD_ERROR === "true",
  },
  turbopack: {},
  serverExternalPackages: ["pino-pretty", "lokijs", "encoding", "thread-stream"],
  webpack: (config: any) => {
    config.resolve.fallback = { fs: false, net: false, tls: false };
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

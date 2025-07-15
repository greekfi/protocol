import type { Metadata } from "next";

const baseUrl = process.env.VERCEL_PROJECT_PRODUCTION_URL
  ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`
  : `http://localhost:${process.env.PORT || 3000}`;
const titleTemplate = "%s | Greek Fi Defi Options";

export const getMetadata = ({
  title,
  description,
  imageRelativePath = "/og-image.png",
}: {
  title: string;
  description: string;
  imageRelativePath?: string;
}): Metadata => {
  const imageUrl = `${baseUrl}${imageRelativePath}`;

  return {
    metadataBase: new URL(baseUrl),
    title: {
      default: title,
      template: titleTemplate,
    },
    description: description,
    openGraph: {
      title: {
        default: title,
        template: titleTemplate,
      },
      description: description,
      images: [
        {
          url: imageUrl,
          width: 1200,
          height: 630,
          alt: "Greek Fi Defi Options Preview",
        },
      ],
      type: "website",
      siteName: "Greek Fi Defi Options",
    },
    twitter: {
      card: "summary_large_image",
      title: {
        default: title,
        template: titleTemplate,
      },
      description: description,
      images: [imageUrl],
      creator: "@greekdotfi",
    },
    icons: {
      icon: [
        { url: "/favicon.ico", sizes: "any", type: "image/x-icon" },
        { url: "/favicon.png", sizes: "32x32", type: "image/png" },
        { url: "/helmet.svg", sizes: "any", type: "image/svg+xml" },
      ],
      apple: [{ url: "/helmet-white.png", sizes: "180x180", type: "image/png" }],
    },
    manifest: "/manifest.json",
    viewport: "width=device-width, initial-scale=1",
    themeColor: "#000000",
  };
};

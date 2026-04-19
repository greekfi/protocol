// @ts-nocheck
import Link from "next/link";

export default function NotFound() {
  return (
    <div className="flex items-center h-full flex-1 justify-center bg-gray-100 dark:bg-gray-900">
      <div className="text-center">
        <h1 className="text-6xl font-bold m-0 mb-1">404</h1>
        <h2 className="text-2xl font-semibold m-0">Page Not Found</h2>
        <p className="text-gray-600 dark:text-gray-400 m-0 mb-4">
          The page you&apos;re looking for doesn&apos;t exist.
        </p>
        <Link
          href="/"
          className="inline-block px-6 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
        >
          Go Home
        </Link>
      </div>
    </div>
  );
}

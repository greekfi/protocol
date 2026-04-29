"use client";

import Link from "next/link";
import { FOOTER_NAV, SERIF_STACK } from "./SiteHeader";

/**
 * Shared site footer — same nav set as the header plus the legal/social
 * extras, with copyright underneath. Instrument Serif throughout.
 */
export function SiteFooter() {
  return (
    <footer style={{ fontFamily: SERIF_STACK }} className="py-12 px-6">
      <div className="max-w-7xl mx-auto flex flex-col items-center gap-8 text-center">
        <div className="flex flex-wrap items-center justify-center gap-x-8 gap-y-3 text-base sm:text-lg">
          {FOOTER_NAV.map(item =>
            item.external ? (
              <a
                key={item.label}
                href={item.href}
                target="_blank"
                rel="noopener noreferrer"
                className="text-gray-300 hover:text-blue-300 transition-colors"
              >
                {item.label}
              </a>
            ) : (
              <Link
                key={item.label}
                href={item.href}
                className="text-gray-300 hover:text-blue-300 transition-colors"
              >
                {item.label}
              </Link>
            ),
          )}
        </div>
        <div className="w-full pt-6 border-t border-gray-800">
          <p className="text-gray-500">© Greek Fi, Inc. 2026</p>
        </div>
      </div>
    </footer>
  );
}

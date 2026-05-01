import type { ReactNode } from "react";

interface HintProps {
  children: ReactNode;
  /** Tooltip body. Strings render as a single block; arrays render one line per entry. */
  tip: string | string[] | ReactNode;
  /** Width of the tooltip box; defaults to a comfortable 16rem. */
  width?: string;
  /** Open above the trigger instead of below (default below). */
  above?: boolean;
}

/**
 * Hover/focus-revealed tooltip styled to match the rest of this app
 * (ModeToggle / YieldPanel). The trigger renders inline with a dotted
 * underline so the user knows it's interactive. The tooltip itself sits
 * below the trigger by default.
 */
export function Hint({ children, tip, width = "w-64", above = false }: HintProps) {
  const body =
    Array.isArray(tip) ? (
      <ul className="space-y-1">
        {tip.map((line, i) => (
          <li key={i}>{line}</li>
        ))}
      </ul>
    ) : (
      tip
    );

  const position = above ? "bottom-full mb-2" : "top-full mt-2";

  return (
    <span tabIndex={0} className="group relative inline-block cursor-help focus:outline-none">
      <span className="border-b border-dotted border-gray-500/60">{children}</span>
      <span
        role="tooltip"
        className={`pointer-events-none absolute left-0 ${position} ${width} p-2 rounded-lg border border-gray-700 bg-black/95 text-[11px] normal-case tracking-normal text-gray-300 shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible group-focus:opacity-100 group-focus:visible transition-opacity z-20`}
      >
        {body}
      </span>
    </span>
  );
}

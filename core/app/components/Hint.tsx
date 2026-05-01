import type { ReactNode } from "react";

interface HintProps {
  children: ReactNode;
  /** Tooltip body. Strings render as a single block; arrays render one line per entry. */
  tip: string | string[] | ReactNode;
  /** Width of the tooltip box; defaults to w-64. */
  width?: string;
  /** Open above the trigger instead of below (default below). */
  above?: boolean;
  /** Add a dotted underline under the trigger to hint at interactivity.
   *  Useful for inline text triggers; turn off when wrapping a button or
   *  pre-styled element. Defaults to true. */
  underline?: boolean;
}

/**
 * Hover/focus-revealed tooltip styled after the /yield ModeToggle: a black
 * rounded card that fades in centred below the trigger. Use this anywhere
 * a `title=` attribute would otherwise carry an explanation — it renders
 * multi-line content properly and matches the rest of the app's chrome.
 */
export function Hint({ children, tip, width = "w-64", above = false, underline = true }: HintProps) {
  const body = Array.isArray(tip) ? (
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
      <span className={underline ? "border-b border-dotted border-gray-500/60" : ""}>{children}</span>
      <span
        role="tooltip"
        className={`pointer-events-none absolute left-1/2 -translate-x-1/2 ${position} ${width} p-3 rounded-lg border border-gray-700 bg-black/95 text-xs normal-case tracking-normal text-gray-300 shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible group-focus:opacity-100 group-focus:visible transition-opacity z-20`}
      >
        {body}
      </span>
    </span>
  );
}

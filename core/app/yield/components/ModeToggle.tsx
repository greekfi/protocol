import clsx from "clsx";

export type YieldMode = "calls" | "puts";

interface ModeToggleProps {
  mode: YieldMode;
  onChange: (m: YieldMode) => void;
}

const TOOLTIPS: Record<YieldMode, string> = {
  calls:
    "Covered call: you deposit a token you already hold (e.g. WETH) and write a call on it. The buyer pays you a premium upfront. If price stays at or below strike at expiry, you keep the premium AND your tokens. If price ends above strike, your tokens are sold at the strike price — you still keep the premium and the upside up to the strike.",
  puts:
    "Covered put: you deposit stablecoin (e.g. USDC) and write a put on a token. The buyer pays you a premium upfront. If price stays at or above strike at expiry, you keep the premium AND your stablecoin. If price ends below strike, you buy the token at the strike price using your stablecoin — you still keep the premium and a discounted entry into the token.",
};

export function ModeToggle({ mode, onChange }: ModeToggleProps) {
  const btn = (active: boolean) =>
    clsx(
      "px-5 py-3 rounded-lg border text-sm font-medium transition-colors",
      active
        ? "bg-[#2F50FF]/15 border-[#2F50FF] text-[#35F3FF]"
        : "bg-black/40 border-gray-800 text-gray-400 hover:text-[#35F3FF] hover:border-[#2F50FF]/60",
    );

  return (
    <div className="flex flex-wrap justify-center gap-2">
      <ModeButton
        active={mode === "calls"}
        onClick={() => onChange("calls")}
        label="Earn Yield from Covered Calls on Tokens"
        tooltip={TOOLTIPS.calls}
        className={btn(mode === "calls")}
      />
      <ModeButton
        active={mode === "puts"}
        onClick={() => onChange("puts")}
        label="Earn Yield from Covered Puts on Stablecoins"
        tooltip={TOOLTIPS.puts}
        className={btn(mode === "puts")}
      />
    </div>
  );
}

/**
 * Button + hover/focus-revealed tooltip describing what the mode actually
 * does. The tooltip wrapper sits *outside* the button so hovering it doesn't
 * fight with the button's own click target.
 */
function ModeButton({
  active,
  onClick,
  label,
  tooltip,
  className,
}: {
  active: boolean;
  onClick: () => void;
  label: string;
  tooltip: string;
  className: string;
}) {
  return (
    <span className="group relative inline-flex">
      <button
        type="button"
        className={className}
        onClick={onClick}
        aria-pressed={active}
        aria-describedby={`mode-tooltip-${label}`}
      >
        {label}
      </button>
      <span
        id={`mode-tooltip-${label}`}
        role="tooltip"
        className="pointer-events-none absolute left-1/2 top-full mt-2 w-80 -translate-x-1/2 p-3 rounded-lg border border-gray-700 bg-black/95 text-xs text-gray-300 shadow-lg opacity-0 invisible group-hover:opacity-100 group-hover:visible group-focus-within:opacity-100 group-focus-within:visible transition-opacity z-20"
      >
        {tooltip}
      </span>
    </span>
  );
}

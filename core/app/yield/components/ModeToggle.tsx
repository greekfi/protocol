import clsx from "clsx";

export type YieldMode = "calls" | "puts";

interface ModeToggleProps {
  mode: YieldMode;
  onChange: (m: YieldMode) => void;
}

export function ModeToggle({ mode, onChange }: ModeToggleProps) {
  const btn = (active: boolean) =>
    clsx(
      "px-5 py-3 rounded-lg border text-sm font-medium transition-colors",
      active
        ? "bg-[#2F50FF]/15 border-[#2F50FF] text-[#35F3FF]"
        : "bg-black/40 border-gray-800 text-gray-400 hover:text-[#35F3FF] hover:border-[#2F50FF]/60",
    );

  return (
    <div className="flex gap-2">
      <button type="button" className={btn(mode === "calls")} onClick={() => onChange("calls")}>
        Covered Calls on Tokens
      </button>
      <button type="button" className={btn(mode === "puts")} onClick={() => onChange("puts")}>
        Covered Puts on Stablecoins
      </button>
    </div>
  );
}

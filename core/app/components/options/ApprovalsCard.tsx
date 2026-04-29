import type { ReactNode } from "react";
import clsx from "clsx";
import { useAccount } from "wagmi";

interface Step {
  label: string;
  done: boolean;
  pending: boolean;
  onAction?: () => void;
  title?: string;
}

export interface BalanceRow {
  label: string;
  value: string;
  dim?: boolean;
  /** When present, renders as a boxed two-line row: label+value on top,
   *  this node underneath separated by a soft divider. */
  bottomRow?: ReactNode;
}

interface ApprovalsCardProps {
  steps: Step[];
  balances?: BalanceRow[];
}

export function ApprovalsCard({ steps, balances }: ApprovalsCardProps) {
  const { isConnected } = useAccount();
  // Balances and approvals only make sense for a connected wallet — both are
  // wallet-scoped (your token balance, your allowance to the protocol). Hide
  // the whole card when no wallet, instead of showing an empty/zero state.
  if (!isConnected) return null;

  const allDone = steps.every(s => s.done);

  return (
    <div
      className={clsx(
        "h-full rounded-lg border p-3 transition-colors",
        allDone ? "border-emerald-500/30 bg-emerald-500/5" : "border-[#FF8300]/40 bg-[#FF8300]/5",
      )}
    >
      {balances && balances.length > 0 && (
        <>
          <div className="mb-1 text-[11px] uppercase tracking-wider text-gray-400 font-semibold">
            Balances
          </div>
          <ul className="mb-3 flex flex-col gap-1.5 text-sm tabular-nums">
            {balances.map(b =>
              b.bottomRow ? (
                <li
                  key={b.label}
                  className="rounded-md border border-gray-700/60 bg-black/30 overflow-hidden"
                >
                  <div className="flex items-center justify-between gap-3 px-2 py-1.5">
                    <span className="text-gray-500 text-xs uppercase tracking-wider">{b.label}</span>
                    <span className={clsx("text-blue-100", b.dim && "text-gray-500")}>{b.value}</span>
                  </div>
                  <div className="border-t border-gray-700/40 px-2 py-1.5">{b.bottomRow}</div>
                </li>
              ) : (
                <li key={b.label} className="flex items-center justify-between gap-3">
                  <span className="text-gray-500 text-xs uppercase tracking-wider">{b.label}</span>
                  <span className={clsx("text-blue-100", b.dim && "text-gray-500")}>{b.value}</span>
                </li>
              ),
            )}
          </ul>
        </>
      )}

      {steps.length > 0 && (
      <div className="flex items-center justify-between mb-2">
        <span className="text-[11px] uppercase tracking-wider text-gray-400 font-semibold">
          Approvals
        </span>
        {allDone && <span className="text-xs text-emerald-300">All set ✓</span>}
      </div>
      )}

      {steps.length > 0 && (
      <ul className="flex flex-col gap-1.5">
        {steps.map(step => (
          <li key={step.label} className="flex items-center justify-between gap-3 text-sm">
            <span className="flex items-center gap-2 min-w-0">
              <span
                className={clsx(
                  "inline-flex items-center justify-center w-4 h-4 rounded-full text-[10px] font-bold shrink-0",
                  step.done
                    ? "bg-emerald-500/80 text-black"
                    : "bg-gray-700 text-gray-400 border border-gray-600",
                )}
                aria-hidden
              >
                {step.done ? "✓" : ""}
              </span>
              <span
                className={clsx("truncate", step.done ? "text-gray-500" : "text-gray-300")}
                title={step.title}
              >
                {step.label}
              </span>
            </span>
            {!step.done && step.onAction && (
              <button
                type="button"
                onClick={step.onAction}
                disabled={step.pending}
                className="px-2.5 py-1 rounded-md bg-[#FF8300] hover:bg-[#e07400] text-black text-xs font-semibold disabled:opacity-50 transition-colors shrink-0"
              >
                {step.pending ? "…" : "Approve"}
              </button>
            )}
          </li>
        ))}
      </ul>
      )}
    </div>
  );
}

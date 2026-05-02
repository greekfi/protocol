import type { ReactNode } from "react";
import { Hint } from "./Hint";

export interface ApprovalStep {
  label: string;
  done: boolean;
  /** Half-done (e.g. one of two layers complete) — pill colour shifts to pink. */
  partial?: boolean;
  pending: boolean;
  onAction?: () => void;
  /** Tooltip body — string, array of lines, or arbitrary node. */
  title?: string | string[] | ReactNode;
}

interface ApprovalsListProps {
  steps: ApprovalStep[];
}

const PILL_BASE =
  "inline-flex items-center justify-center min-w-[2.5rem] px-1 py-0.5 rounded-md text-xs font-semibold transition-colors shrink-0";

/**
 * Single-column list of approval rows. Each row is "[Approve] label" while
 * pending and "[✓] label" once done. The pill turns pink for half-done
 * (e.g. one of two layers complete). Used by /trade and /yield.
 */
export function ApprovalsList({ steps }: ApprovalsListProps) {
  return (
    <ul className="flex flex-col gap-1.5 text-sm">
      {steps.map(step => (
        <li key={step.label} className="flex items-center gap-2 min-w-0">
          {step.done ? (
            <span
              className="inline-flex items-center justify-center min-w-[2.5rem] text-emerald-400 text-base shrink-0"
              aria-hidden
            >
              ✓
            </span>
          ) : (
            <button
              type="button"
              onClick={step.onAction}
              disabled={step.pending || !step.onAction}
              className={`${PILL_BASE} ${
                step.partial
                  ? "bg-pink-500 hover:bg-pink-400"
                  : "bg-[#FF8300] hover:bg-[#e07400]"
              } text-black disabled:opacity-50`}
            >
              {step.pending ? "…" : "Approve"}
            </button>
          )}
          <span className={`truncate ${step.done ? "text-gray-500" : "text-gray-300"}`}>
            {step.title ? (
              <Hint tip={step.title} above>
                {step.label}
              </Hint>
            ) : (
              step.label
            )}
          </span>
        </li>
      ))}
    </ul>
  );
}

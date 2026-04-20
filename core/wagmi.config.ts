import { defineConfig } from "@wagmi/cli";
import { react } from "@wagmi/cli/plugins";
import foundryContracts from "../abi/chains/foundry";

// Contracts we want typed hooks for. Pulled from the generated foundry chain file
// because it has every deployed protocol contract (same ABIs across chains).
const WANTED = ["Factory", "Option", "Collateral", "YieldVault"] as const;

// Our filtered ABI strips empty `inputs`/`outputs` arrays, but abitype (used by
// @wagmi/cli) requires them to be present. Normalize before handing off.
type AbiEntry = Record<string, unknown> & { type?: string; name?: string };
function normalizeAbi(abi: readonly AbiEntry[]): AbiEntry[] {
  return abi
    .filter(e => !(typeof e.name === "string" && e.name.startsWith("_")))
    .map(e => {
      const out: AbiEntry = { ...e };
      if (e.type === "function" || e.type === "constructor" || e.type === "error" || e.type === "event") {
        if (!Array.isArray(out.inputs)) out.inputs = [];
      }
      if (e.type === "function" || e.type === "error") {
        if (!Array.isArray(out.outputs)) out.outputs = [];
      }
      return out;
    });
}

const contracts = WANTED.filter(
  (name): name is (typeof WANTED)[number] => name in foundryContracts,
).map(name => {
  const entry = (foundryContracts as unknown as Record<string, { abi: readonly AbiEntry[] }>)[name];
  return {
    name,
    abi: normalizeAbi(entry.abi) as unknown as readonly never[],
  };
});

export default defineConfig({
  out: "generated.ts",
  contracts,
  plugins: [react()],
});

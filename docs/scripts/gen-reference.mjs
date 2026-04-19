#!/usr/bin/env node
// Post-process `forge doc` output into Docusaurus-ready pages under docs/reference/generated/.
//
// Expects `forge doc --out docs` to have been run from the foundry workspace beforehand
// (`yarn workspace @greek/foundry docs:gen`). We then cherry-pick the first-party contracts
// and normalise link paths + frontmatter.
//
// Run via `yarn docs:gen` from the root (which invokes the foundry step then this script).

import { promises as fs } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, "..", "..");
const SRC = path.join(ROOT, "foundry", "docs", "src", "contracts");
const DEST = path.join(ROOT, "docs", "docs", "reference", "generated");

// What to copy. forgeRelPath (inside foundry/docs/src/contracts) → docusaurus relative path.
const MAP = [
  // Core
  { from: "Option.sol/contract.Option.md", to: "contracts/Option.md", title: "Option", group: "core" },
  { from: "Collateral.sol/contract.Collateral.md", to: "contracts/Collateral.md", title: "Collateral", group: "core" },
  { from: "Factory.sol/contract.Factory.md", to: "contracts/Factory.md", title: "Factory", group: "core" },
  { from: "YieldVault.sol/contract.YieldVault.md", to: "contracts/YieldVault.md", title: "YieldVault", group: "core" },
  { from: "OptionUtils.sol/library.OptionUtils.md", to: "contracts/OptionUtils.md", title: "OptionUtils", group: "core" },
  // Oracles
  { from: "oracles/IPriceOracle.sol/interface.IPriceOracle.md", to: "oracles/IPriceOracle.md", title: "IPriceOracle", group: "oracles" },
  { from: "oracles/UniV3Oracle.sol/contract.UniV3Oracle.md", to: "oracles/UniV3Oracle.md", title: "UniV3Oracle", group: "oracles" },
  // Interfaces (first-party only)
  { from: "interfaces/IOption.sol/interface.IOption.md", to: "interfaces/IOption.md", title: "IOption", group: "interfaces" },
  { from: "interfaces/ICollateral.sol/interface.ICollateral.md", to: "interfaces/ICollateral.md", title: "ICollateral", group: "interfaces" },
  { from: "interfaces/IFactory.sol/interface.IFactory.md", to: "interfaces/IFactory.md", title: "IFactory", group: "interfaces" },
];

// Maps from forge-doc link paths to our destination slugs for intra-doc link rewriting.
const LINK_MAP = new Map();
for (const m of MAP) {
  // forge doc emits links rooted at /contracts/...
  LINK_MAP.set(`/contracts/${m.from}`, toDocusaurusSlug(m.to));
  // Also accept relative forms like ../../Option.sol/...
  LINK_MAP.set(m.from, toDocusaurusSlug(m.to));
}

function toDocusaurusSlug(rel) {
  // "contracts/Option.md" → "/reference/generated/contracts/Option"
  return `/reference/generated/${rel.replace(/\.md$/, "")}`;
}

async function rimraf(p) {
  await fs.rm(p, { recursive: true, force: true });
}

async function ensureDir(p) {
  await fs.mkdir(p, { recursive: true });
}

function rewriteLinks(md) {
  // Walk `[text](href)` pairs. Two cases:
  //   1. href points to one of our emitted pages — rewrite to the Docusaurus slug.
  //   2. href points to something else (`/contracts/interfaces/IERC1271.sol/...` etc., a third-party
  //      interface we don't emit) — unwrap the link, keep the text as plain `code`.
  return md.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (match, text, href) => {
    for (const [forgePath, slug] of LINK_MAP) {
      if (href.includes(forgePath)) {
        const rest = href.slice(href.indexOf(forgePath) + forgePath.length); // e.g. "#mint"
        return `[${text}](${slug}${rest})`;
      }
    }
    // Leave absolute external links alone.
    if (/^https?:\/\//.test(href)) return match;
    // Otherwise drop the broken internal link, keep the label as inline code.
    return "`" + text + "`";
  });
}

function stripFirstH1(md) {
  // forge doc leads each file with "# <ContractName>" + a "Git Source" line. We replace both
  // with Docusaurus frontmatter.
  const lines = md.split("\n");
  while (lines.length && (lines[0].trim() === "" || /^#\s/.test(lines[0]) || lines[0].startsWith("[Git Source]"))) {
    lines.shift();
  }
  return lines.join("\n");
}

// MDX parses {X} as a JS expression. Our NatSpec uses {ContractName} as cross-references, so we
// need to walk the markdown outside of code blocks and escape `{...}` by backticking it. That also
// renders it as inline code, which is the visual treatment these references want anyway.
function escapeJsxReferences(md) {
  const parts = md.split(/(^```[\s\S]*?^```)/m); // odd indices are fenced code blocks
  return parts
    .map((segment, i) => {
      if (i % 2 === 1) return segment; // leave code fences alone
      // Walk inline code spans too — don't double-escape what's already inside backticks.
      return segment
        .split(/(`[^`\n]*`)/g)
        .map((chunk, j) => {
          if (j % 2 === 1) return chunk; // inside an inline code span
          // Match {Identifier}, {Contract.method}, or {Contract-method} (NatSpec cross-references).
          // Forge-doc carries these through from our source, and MDX would otherwise parse them
          // as JSX expressions.
          return chunk.replace(/\{([A-Za-z_][A-Za-z0-9_.-]*)\}/g, "`$1`");
        })
        .join("");
    })
    .join("");
}

function frontmatter({ title, sidebar_label, description }) {
  return [
    "---",
    `title: ${title}`,
    `sidebar_label: ${sidebar_label}`,
    description ? `description: ${JSON.stringify(description)}` : null,
    "---",
    "",
  ].filter(Boolean).join("\n");
}

async function processOne(entry) {
  const src = path.join(SRC, entry.from);
  const dest = path.join(DEST, entry.to);
  let md;
  try {
    md = await fs.readFile(src, "utf8");
  } catch (e) {
    if (e.code === "ENOENT") {
      console.error(`[docs:gen] missing ${src} — did you run "yarn workspace @greek/foundry docs:gen" first?`);
      process.exitCode = 1;
      return;
    }
    throw e;
  }

  const body = escapeJsxReferences(rewriteLinks(stripFirstH1(md)));
  const fm = frontmatter({ title: entry.title, sidebar_label: entry.title });
  await ensureDir(path.dirname(dest));
  await fs.writeFile(dest, fm + "\n# " + entry.title + "\n" + body);
}

async function writeGroupIndex(group, entries) {
  const dest = path.join(DEST, group, "index.md");
  const labels = {
    core: { title: "Core Contracts", blurb: "User-facing contracts for minting, exercising, and settling options." },
    oracles: { title: "Oracles", blurb: "Settlement oracle interface and shipped implementations." },
    interfaces: { title: "Interfaces", blurb: "First-party interfaces used by integrators and downstream contracts." },
  }[group];
  const rows = entries.map(
    (e) => `- [\`${e.title}\`](${toDocusaurusSlug(e.to)})`
  ).join("\n");
  const body = [
    frontmatter({ title: labels.title, sidebar_label: labels.title }),
    `# ${labels.title}`,
    "",
    labels.blurb,
    "",
    rows,
    "",
  ].join("\n");
  await ensureDir(path.dirname(dest));
  await fs.writeFile(dest, body);
}

async function writeTopIndex() {
  const body = [
    frontmatter({
      title: "Generated Reference",
      sidebar_label: "Generated",
      description: "Auto-generated per-contract API reference, rendered from NatSpec via `forge doc`.",
    }),
    "# Generated Reference",
    "",
    "These pages are auto-generated from the NatSpec in `foundry/contracts/`. Edit the Solidity source",
    "and run `yarn docs:gen` from the repo root to refresh them.",
    "",
    "- [Core Contracts](/reference/generated/core)",
    "- [Oracles](/reference/generated/oracles)",
    "- [Interfaces](/reference/generated/interfaces)",
    "",
  ].join("\n");
  await ensureDir(DEST);
  await fs.writeFile(path.join(DEST, "index.md"), body);
}

async function main() {
  await rimraf(DEST);
  await ensureDir(DEST);

  for (const entry of MAP) {
    await processOne(entry);
  }

  const byGroup = new Map();
  for (const entry of MAP) {
    if (!byGroup.has(entry.group)) byGroup.set(entry.group, []);
    byGroup.get(entry.group).push(entry);
  }
  for (const [group, entries] of byGroup) {
    await writeGroupIndex(group, entries);
  }
  await writeTopIndex();

  console.log(`[docs:gen] wrote ${MAP.length} contract pages → ${path.relative(ROOT, DEST)}`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});

// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docsSidebar: [
    "index",
    {
      type: "category",
      label: "Fundamentals",
      link: { type: "doc", id: "fundamentals/overview" },
      items: [
        "fundamentals/mint-and-collateralize",
        "fundamentals/tokens",
        "fundamentals/auto-mint-redeem",
        "fundamentals/exercise",
      ],
    },
    "trading",
    {
      type: "category",
      label: "Settlement",
      link: { type: "doc", id: "settlement/overview" },
      items: [
        "settlement/pair-redeem",
        "settlement/oracle-settlement",
        "settlement/oracles",
      ],
    },
    {
      type: "category",
      label: "Reference",
      link: { type: "doc", id: "reference/contracts" },
      items: ["reference/errors", "reference/addresses"],
    },
  ],
};

export default sidebars;

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
      items: [
        "reference/errors",
        "reference/addresses",
        {
          type: "category",
          label: "Generated API",
          link: { type: "doc", id: "reference/generated/index" },
          items: [
            {
              type: "category",
              label: "Core",
              link: { type: "doc", id: "reference/generated/core/index" },
              items: [
                "reference/generated/contracts/Option",
                "reference/generated/contracts/Collateral",
                "reference/generated/contracts/Factory",
                "reference/generated/contracts/YieldVault",
                "reference/generated/contracts/OptionUtils",
              ],
            },
            {
              type: "category",
              label: "Oracles",
              link: { type: "doc", id: "reference/generated/oracles/index" },
              items: [
                "reference/generated/oracles/IPriceOracle",
                "reference/generated/oracles/UniV3Oracle",
              ],
            },
            {
              type: "category",
              label: "Interfaces",
              link: { type: "doc", id: "reference/generated/interfaces/index" },
              items: [
                "reference/generated/interfaces/IOption",
                "reference/generated/interfaces/ICollateral",
                "reference/generated/interfaces/IFactory",
              ],
            },
          ],
        },
      ],
    },
  ],
};

export default sidebars;

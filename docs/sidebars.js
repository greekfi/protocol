// @ts-check

/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  docsSidebar: [
    "index",
    "addresses",
    "fundamentals",
    "trading",
    "settlement",
    {
      type: "category",
      label: "Reference",
      link: { type: "doc", id: "reference/contracts" },
      items: ["reference/api"],
    },
  ],
};

export default sidebars;

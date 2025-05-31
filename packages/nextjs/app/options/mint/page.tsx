"use client";

import { useEffect, useState } from "react";
import Layout from "../../oldapp/Layout";
import OptionsFunctions from "../../oldapp/optionsFunctions";

export default function MintPage() {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return null;
  }

  return (
    <Layout>
      <OptionsFunctions />
    </Layout>
  );
}

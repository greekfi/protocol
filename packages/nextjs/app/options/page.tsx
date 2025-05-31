"use client";

import { useEffect, useState } from "react";
import Layout from "../oldapp/Layout";
import Main from "../oldapp/base";

export default function OptionsPage() {
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return null;
  }

  return (
    <Layout>
      <Main />
    </Layout>
  );
}

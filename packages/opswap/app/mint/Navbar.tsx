"use client";

import React from "react";
import Image from "next/image";
import Link from "next/link";
import { ConnectButton } from "@rainbow-me/rainbowkit";
import logo from "../../public/helmet-white.svg";

const Navbar: React.FC = () => (
  <nav className="flex justify-between w-full">
    <ul className="flex items-center space-x-6">
      <li>
        <Image src={logo} alt="Greek.fi" className="w-24 h-24" />
      </li>
      <li>
        <Link href="/packages/nextjs/public" className="hover:text-blue-500">
          About GreekFi
        </Link>
      </li>
      <li>
        <Link href="https://github.com/greekfi/whitepaper" className="hover:text-blue-500">
          Whitepaper
        </Link>
      </li>
      <li>
        <Link href="mailto:hello@greek.fi" className="hover:text-blue-500 text-blue-300">
          Contact
        </Link>
      </li>
      <li>
        <ConnectButton />
      </li>
    </ul>
  </nav>
);

export default Navbar;

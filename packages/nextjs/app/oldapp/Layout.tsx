import { ReactNode } from "react";

// import { useChainStore } from './config';

interface LayoutProps {
  children: ReactNode;
}

export default function Layout({ children }: LayoutProps) {
  // const { currentChain } = useChainStore();

  return (
    <div className="min-h-screen bg-black text-gray-200">
      {/* <div className="fixed top-0 right-0 p-4 z-50">
        <ChainSelector />
      </div> */}
      {/* <div className="p-4 fixed top-0 left-1/2 transform -translate-x-1/2 bg-blue-500/10 rounded-b-lg border border-blue-300/20 z-50">
        <p className="text-sm text-blue-200">
          Currently on <span className="font-semibold">{currentChain.name}</span>
        </p>
      </div> */}
      {children}
    </div>
  );
}

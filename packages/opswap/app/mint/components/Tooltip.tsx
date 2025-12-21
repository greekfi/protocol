import React from "react";

interface TooltipButtonProps {
  tooltipText: string;
  title?: string;
  className?: string;
}

const Tooltip: React.FC<TooltipButtonProps> = ({
  tooltipText,
  title,
  className = "text-sm text-blue-200 hover:text-blue-300 flex items-center gap-1",
}) => {
  const handleClick = (e: React.MouseEvent<HTMLButtonElement>) => {
    const tooltip = document.createElement("div");
    tooltip.className = "absolute bg-gray-900 text-sm text-gray-200 p-2 rounded shadow-lg -mt-8 -ml-2";
    tooltip.textContent = tooltipText;

    const button = e.currentTarget;
    button.appendChild(tooltip);

    setTimeout(() => {
      tooltip.remove();
    }, 2000);
  };

  return (
    <button type="button" className={className} title={title} onClick={handleClick}>
      <svg
        xmlns="http://www.w3.org/2000/svg"
        fill="none"
        viewBox="0 0 24 24"
        strokeWidth={1.5}
        stroke="currentColor"
        className="w-4 h-4"
      >
        <path
          strokeLinecap="round"
          strokeLinejoin="round"
          d="m11.25 11.25.041-.02a.75.75 0 0 1 1.063.852l-.708 2.836a.75.75 0 0 0 1.063.853l.041-.021M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9-3.75h.008v.008H12V8.25Z"
        />
      </svg>
    </button>
  );
};

export default Tooltip;

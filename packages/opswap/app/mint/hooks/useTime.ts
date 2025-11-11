import { useState, useEffect } from "react";

/**
 * Hook that provides the current time and updates every second.
 * This allows components to check time-based conditions (like expiration)
 * without calling Date.now() during render, which would violate React's purity rules.
 */
export function useTime() {
  // Keep track of the current date's state. `useState` receives an initializer function as its
  // initial state. It only runs once when the hook is called, so only the current date at the
  // time the hook is called is set first.
  const [time, setTime] = useState(() => new Date());

  useEffect(() => {
    // Update the current date every second using `setInterval`.
    const id = setInterval(() => {
      setTime(new Date()); // ✅ Good: non-idempotent code no longer runs in render
    }, 1000);
    // Return a cleanup function so we don't leak the `setInterval` timer.
    return () => clearInterval(id);
  }, []);

  return time;
}

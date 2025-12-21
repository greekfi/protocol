import { useState, useEffect } from "react";

/**
 * Hook that checks if a given expiration timestamp has passed.
 * Checks once when expiration changes and sets up a timer to update when it expires.
 * This avoids re-renders every second.
 *
 * @param expiration - Unix timestamp in seconds when the option expires
 * @returns boolean indicating whether the expiration time has passed
 */
export function useIsExpired(expiration: bigint | undefined): boolean {
  const [isExpired, setIsExpired] = useState(false);

  useEffect(() => {
    if (!expiration) {
      setIsExpired(false);
      return;
    }

    const expirationMs = Number(expiration) * 1000;
    const now = Date.now();

    // Check if already expired
    if (now >= expirationMs) {
      setIsExpired(true);
      return;
    }

    // Not expired yet - set it as not expired
    setIsExpired(false);

    // Set a timer to update when it expires
    const timeUntilExpiration = expirationMs - now;
    const timerId = setTimeout(() => {
      setIsExpired(true);
    }, timeUntilExpiration);

    return () => clearTimeout(timerId);
  }, [expiration]);

  return isExpired;
}

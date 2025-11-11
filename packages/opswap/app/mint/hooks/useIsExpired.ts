import { useTime } from "./useTime";

/**
 * Hook that checks if a given expiration timestamp has passed.
 * Uses the useTime hook to get the current time without calling Date.now() during render.
 *
 * @param expiration - Unix timestamp in seconds when the option expires
 * @returns boolean indicating whether the expiration time has passed
 */
export function useIsExpired(expiration: bigint | undefined): boolean {
  const currentTime = useTime();

  if (!expiration) {
    return false;
  }

  return currentTime.getTime() / 1000 > Number(expiration);
}

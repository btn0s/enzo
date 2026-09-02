export function shouldDisablePushToken(
  status: number,
  reason: string | undefined,
) {
  return status === 410
    || reason === "BadDeviceToken"
    || reason === "Unregistered";
}

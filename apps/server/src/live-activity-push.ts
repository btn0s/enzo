const APPLE_REFERENCE_DATE_OFFSET = 978_307_200;

export function liveActivityPayload(nextFeedAt: string | null, timestamp: number) {
  const event = nextFeedAt === null ? "end" : "update";
  return {
    aps: {
      timestamp,
      event,
      "content-state": {
        nextFeedAt: nextFeedAt === null
          ? null
          : new Date(nextFeedAt).getTime() / 1_000 - APPLE_REFERENCE_DATE_OFFSET,
      },
      ...(event === "end" ? { "dismissal-date": timestamp } : {}),
    },
  };
}

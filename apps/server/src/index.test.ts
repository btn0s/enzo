import { describe, expect, test } from "bun:test";
import { liveActivityPayload } from "./live-activity-push";
import { widgetPushPayload } from "./widget-push";
import { shouldDisablePushToken } from "./apns";

const appleReferenceDateOffset = 978_307_200;

describe("liveActivityPayload", () => {
  test("encodes the next feed using Swift Date's reference epoch", () => {
    const nextFeedAt = "2026-09-02T03:25:00.000Z";
    const timestamp = 1_788_319_500;

    expect(liveActivityPayload(nextFeedAt, timestamp)).toEqual({
      aps: {
        timestamp,
        event: "update",
        "content-state": {
          nextFeedAt: new Date(nextFeedAt).getTime() / 1_000 - appleReferenceDateOffset,
        },
      },
    });
  });

  test("ends and immediately dismisses the activity without a next feed", () => {
    const timestamp = 1_788_319_500;

    expect(liveActivityPayload(null, timestamp)).toEqual({
      aps: {
        timestamp,
        event: "end",
        "content-state": { nextFeedAt: null },
        "dismissal-date": timestamp,
      },
    });
  });
});

describe("widgetPushPayload", () => {
  test("requests a WidgetKit timeline refresh", () => {
    expect(widgetPushPayload()).toEqual({
      aps: {
        "content-changed": true,
      },
    });
  });
});

describe("shouldDisablePushToken", () => {
  test("keeps tokens when APNs reports a topic configuration error", () => {
    expect(shouldDisablePushToken(400, "DeviceTokenNotForTopic")).toBe(false);
  });

  test("retires tokens that APNs no longer recognizes", () => {
    expect(shouldDisablePushToken(410, "Unregistered")).toBe(true);
    expect(shouldDisablePushToken(400, "BadDeviceToken")).toBe(true);
  });
});

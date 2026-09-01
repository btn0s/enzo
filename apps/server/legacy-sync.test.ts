import { describe, expect, test } from "bun:test";
import { syncLegacyMutation, type LegacySyncEnvelope } from "./legacy-sync";

const envelope: LegacySyncEnvelope = {
  operation: "upsert",
  eventID: "feed-1",
  event: { id: "feed-1", type: "feed" },
  updateReminder: true,
  nextFeedAt: "2026-09-01T13:00:00.000Z",
};

describe("syncLegacyMutation", () => {
  test("returns success after the adapter accepts the mutation", async () => {
    const result = await syncLegacyMutation(envelope, {
      execute: async () => {},
      attempts: 3,
    });

    expect(result).toEqual({ ok: true, attempts: 1 });
  });

  test("retries an idempotent mutation before reporting success", async () => {
    let calls = 0;
    const delays: number[] = [];
    const result = await syncLegacyMutation(envelope, {
      execute: async () => {
        calls += 1;
        if (calls < 3) throw new Error("temporary failure");
      },
      sleep: async (milliseconds) => { delays.push(milliseconds); },
      attempts: 3,
    });

    expect(result).toEqual({ ok: true, attempts: 3 });
    expect(delays).toEqual([1000, 2000]);
  });

  test("returns the final error after the retry limit", async () => {
    const result = await syncLegacyMutation(envelope, {
      execute: async () => { throw new Error("endpoint unavailable"); },
      sleep: async () => {},
      attempts: 2,
    });

    expect(result).toEqual({
      ok: false,
      attempts: 2,
      error: "endpoint unavailable",
    });
  });
});

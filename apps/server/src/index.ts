import { shouldDisablePushToken } from "./apns";
import { liveActivityPayload } from "./live-activity-push";
import { widgetPushPayload } from "./widget-push";

/**
 * Enzo API on Cloudflare Workers. D1 is the durable source of truth.
 * Every /api/* route requires a bearer token (ENZO_API_TOKEN secret).
 */

type EventType = "feed" | "diaper";

type EventRow = {
  id: string;
  occurred_at: string;
  type: EventType;
  milk_type: "formula" | "breast-milk" | null;
  amount_ml: number | null;
  pee: number;
  poop: number;
  resets_timer: number;
  notes: string;
  source: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

type ProfileRow = {
  id: number;
  birth_at: string;
  feed_interval_minutes: number;
  updated_at: string;
};
type PushEnvironment = "sandbox" | "production";

type PushDeviceRow = {
  token: string;
  environment: PushEnvironment;
};

type LiveActivityTokenRow = {
  token: string;
  activity_id: string;
  event_id: string;
  environment: PushEnvironment;
};
type WidgetPushTokenRow = {
  token: string;
  environment: PushEnvironment;
};



type CheckupRow = {
  id: string;
  occurred_at: string;
  weight_kg: number | null;
  feed_interval_minutes: number | null;
  feeds_min: number | null;
  feeds_max: number | null;
  bottle_ml: number | null;
  milk_ml_min: number | null;
  milk_ml_max: number | null;
  pee_min: number | null;
  poop_min: number | null;
  notes: string;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

// [column, jsonKey, min, max]. A min of 0 is exclusive (a weight or volume of
// zero is meaningless); other minimums are inclusive.
const CHECKUP_FIELDS = [
  ["weight_kg", "weightKg", 0, 30],
  ["feed_interval_minutes", "feedIntervalMinutes", 30, 720],
  ["feeds_min", "feedsMin", 1, 24],
  ["feeds_max", "feedsMax", 1, 24],
  ["bottle_ml", "bottleMl", 0, 500],
  ["milk_ml_min", "milkMlMin", 0, 3000],
  ["milk_ml_max", "milkMlMax", 0, 3000],
  ["pee_min", "peeMin", 0, 30],
  ["poop_min", "poopMin", 0, 30],
] as const;

const COUNT_FIELDS: Record<string, true> = { peeMin: true, poopMin: true };

function serializeCheckup(row: CheckupRow) {
  const out: Record<string, unknown> = {
    id: row.id,
    occurredAt: new Date(row.occurred_at).toISOString(),
    notes: row.notes,
  };
  for (const [column, key] of CHECKUP_FIELDS) {
    out[key] = row[column] === null ? null : Number(row[column]);
  }
  return out;
}

function parseCheckup(body: Record<string, unknown>) {
  const checkup: Record<string, unknown> = {
    id: typeof body.id === "string" && body.id ? body.id : crypto.randomUUID(),
    occurredAt: parseOccurredAt(body.occurredAt),
    notes: typeof body.notes === "string" ? body.notes.trim() : "",
  };
  for (const [, key, min, max] of CHECKUP_FIELDS) {
    const raw = body[key];
    if (raw === null || raw === undefined || raw === "") {
      checkup[key] = null;
      continue;
    }
    const value = Number(raw);
    const tooLow = min === 0 && !COUNT_FIELDS[key] ? value <= 0 : value < min;
    if (!Number.isFinite(value) || tooLow || value > max) {
      throw new Error(`${key} must be between ${min} and ${max}`);
    }
    checkup[key] = value;
  }
  const feedsMin = checkup.feedsMin as number | null;
  const feedsMax = checkup.feedsMax as number | null;
  if (feedsMin !== null && feedsMax !== null && feedsMin > feedsMax) {
    throw new Error("feedsMin must not exceed feedsMax");
  }
  const milkMin = checkup.milkMlMin as number | null;
  const milkMax = checkup.milkMlMax as number | null;
  if (milkMin !== null && milkMax !== null && milkMin > milkMax) {
    throw new Error("milkMlMin must not exceed milkMlMax");
  }
  return checkup as {
    id: string; occurredAt: string; notes: string;
    weightKg: number | null; feedIntervalMinutes: number | null;
    feedsMin: number | null; feedsMax: number | null; bottleMl: number | null;
    milkMlMin: number | null; milkMlMax: number | null;
    peeMin: number | null; poopMin: number | null;
  };
}

function json(value: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  return new Response(JSON.stringify(value), { ...init, headers });
}

const encoder = new TextEncoder();

function authorized(request: Request, env: Env) {
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  const expected = encoder.encode(env.ENZO_API_TOKEN);
  const provided = encoder.encode(token);
  if (expected.byteLength === 0 || provided.byteLength !== expected.byteLength) {
    return false;
  }
  return crypto.subtle.timingSafeEqual(provided, expected);
}

function localDay(value: string | Date, timezone: string) {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}

function serializeEvent(row: EventRow) {
  const base = {
    id: row.id,
    occurredAt: new Date(row.occurred_at).toISOString(),
    notes: row.notes,
  };
  if (row.type === "feed") {
    return {
      ...base,
      type: "feed" as const,
      feed: {
        milkType: row.milk_type!,
        amountMl: row.amount_ml === null ? null : Number(row.amount_ml),
        resetsTimer: row.resets_timer === 1,
      },
    };
  }
  return {
    ...base,
    type: "diaper" as const,
    diaper: { pee: row.pee === 1, poop: row.poop === 1 },
  };
}

async function readState(env: Env) {
  const timezone = env.ENZO_TIMEZONE;
  const [{ results: rows }, profile, { results: checkupRows }] = await Promise.all([
    env.DB.prepare(
      `SELECT * FROM care_events
       WHERE deleted_at IS NULL
       ORDER BY occurred_at DESC, created_at DESC`,
    ).all<EventRow>(),
    env.DB.prepare("SELECT * FROM profile WHERE id = 1").first<ProfileRow>(),
    env.DB.prepare(
      `SELECT * FROM checkups
       WHERE deleted_at IS NULL
       ORDER BY occurred_at DESC, created_at DESC`,
    ).all<CheckupRow>(),
  ]);

  // The active plan is the latest checkup that has already happened. A checkup
  // may override the family-controlled interval; otherwise the shared profile
  // setting applies.
  const nowIso = new Date().toISOString();
  const activeCheckup = checkupRows.find((row) => row.occurred_at <= nowIso) ?? null;
  const defaultIntervalMinutes = Number(profile!.feed_interval_minutes);
  const intervalMinutes = activeCheckup?.feed_interval_minutes ?? defaultIntervalMinutes;

  const today = localDay(new Date(), timezone);
  const todayRows = rows.filter((row) => localDay(row.occurred_at, timezone) === today);
  const lastResettingFeed = rows.find((row) => row.type === "feed" && row.resets_timer === 1);
  const lastFeed = rows.find((row) => row.type === "feed");
  const nextFeedAt = lastResettingFeed
    ? new Date(new Date(lastResettingFeed.occurred_at).getTime() + intervalMinutes * 60_000).toISOString()
    : null;

  return {
    prototype: true,
    storage: "d1",
    timezone,
    intervalMinutes,
    now: nowIso,
    nextFeedAt,
    profile: {
      birthAt: new Date(profile!.birth_at).toISOString(),
      feedIntervalMinutes: defaultIntervalMinutes,
    },
    checkups: checkupRows.map(serializeCheckup),
    activeCheckupId: activeCheckup?.id ?? null,
    lastFeed: lastFeed ? serializeEvent(lastFeed) : null,
    today: {
      milkMl: todayRows.reduce((sum, row) => sum + Number(row.amount_ml ?? 0), 0),
      feeds: todayRows.filter((row) => row.type === "feed").length,
      pees: todayRows.filter((row) => row.pee === 1).length,
      poops: todayRows.filter((row) => row.poop === 1).length,
    },
    events: rows.map(serializeEvent),
  };
}

function parseOccurredAt(value: unknown) {
  const date = new Date(typeof value === "string" ? value : Date.now());
  if (Number.isNaN(date.getTime())) throw new Error("occurredAt must be a valid date");
  return date.toISOString();
}

function parseEvent(body: Record<string, unknown>, fixedType?: EventType) {
  const type = fixedType ?? body.type;
  if (type !== "feed" && type !== "diaper") throw new Error("type must be feed or diaper");
  const event = {
    id: typeof body.id === "string" && body.id ? body.id : crypto.randomUUID(),
    occurredAt: parseOccurredAt(body.occurredAt),
    type,
    milkType: null as EventRow["milk_type"],
    amountMl: null as number | null,
    pee: false,
    poop: false,
    resetsTimer: body.resetsTimer !== false,
    notes: typeof body.notes === "string" ? body.notes.trim() : "",
  };

  if (type === "feed") {
    const feed = (typeof body.feed === "object" && body.feed !== null
      ? body.feed
      : body) as Record<string, unknown>;
    if (feed.milkType !== "formula" && feed.milkType !== "breast-milk") {
      throw new Error("milkType must be formula or breast-milk");
    }
    event.milkType = feed.milkType;
    if (feed.amountMl !== null && feed.amountMl !== undefined && feed.amountMl !== "") {
      const amount = Number(feed.amountMl);
      if (!Number.isFinite(amount) || amount <= 0 || amount > 1000) {
        throw new Error("amountMl must be between 0 and 1000");
      }
      event.amountMl = amount;
    }
    event.resetsTimer = feed.resetsTimer !== false;
  } else {
    const diaper = (typeof body.diaper === "object" && body.diaper !== null
      ? body.diaper
      : body) as Record<string, unknown>;
    event.pee = diaper.pee === true;
    event.poop = diaper.poop === true;
    event.resetsTimer = false;
    if (!event.pee && !event.poop) throw new Error("a diaper needs pee, poop, or both");
  }
  return event;
}

async function mutationResponse(env: Env, eventId: string) {
  return { ok: true, eventId, state: await readState(env) };
}
let cachedProviderToken: { value: string; issuedAt: number } | undefined;

function base64Url(value: string | ArrayBuffer) {
  const binary = typeof value === "string"
    ? value
    : String.fromCharCode(...new Uint8Array(value));
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function privateKeyBytes(pem: string) {
  const base64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

async function providerToken(env: Env) {
  const now = Math.floor(Date.now() / 1_000);
  if (cachedProviderToken && now - cachedProviderToken.issuedAt < 50 * 60) {
    return cachedProviderToken.value;
  }

  const privateKey = (env as Env & { APNS_PRIVATE_KEY?: string }).APNS_PRIVATE_KEY;
  if (!privateKey) throw new Error("APNS_PRIVATE_KEY is not configured");

  const header = base64Url(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID }));
  const claims = base64Url(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
  const unsignedToken = `${header}.${claims}`;
  const signingKey = await crypto.subtle.importKey(
    "pkcs8",
    privateKeyBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    signingKey,
    encoder.encode(unsignedToken),
  );
  const value = `${unsignedToken}.${base64Url(signature)}`;
  cachedProviderToken = { value, issuedAt: now };
  return value;
}


async function disablePushDevice(env: Env, token: string) {
  await env.DB.prepare(
    `UPDATE push_devices
     SET disabled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE token = ?1`,
  ).bind(token).run();
}

async function disableLiveActivityToken(env: Env, token: string) {
  await env.DB.prepare(
    `UPDATE live_activity_tokens
     SET disabled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE token = ?1`,
  ).bind(token).run();
}
async function disableWidgetPushToken(env: Env, token: string) {
  await env.DB.prepare(
    `UPDATE widget_push_tokens
     SET disabled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
         updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
     WHERE token = ?1`,
  ).bind(token).run();
}

async function nextLiveActivityTimestamp(env: Env) {
  const row = await env.DB.prepare(
    `INSERT INTO push_delivery_state (id, live_activity_timestamp)
     VALUES (1, unixepoch())
     ON CONFLICT (id) DO UPDATE SET
       live_activity_timestamp = MAX(
         push_delivery_state.live_activity_timestamp + 1,
         unixepoch()
       )
     RETURNING live_activity_timestamp`,
  ).first<{ live_activity_timestamp: number }>();
  if (!row) throw new Error("Unable to allocate a Live Activity timestamp");
  return row.live_activity_timestamp;
}



async function sendLiveActivityNotification(
  env: Env,
  authorization: string,
  activity: LiveActivityTokenRow,
  nextFeedAt: string | null,
  timestamp: number,
) {
  const host = activity.environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const response = await fetch(`${host}/3/device/${activity.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${authorization}`,
      "apns-topic": `${env.APNS_TOPIC}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "apns-expiration": "0",
      "apns-collapse-id": "enzo-feed-state",
      "content-type": "application/json",
    },
    body: JSON.stringify(liveActivityPayload(nextFeedAt, timestamp)),
  });
  if (response.ok) return;

  const failure = await response
    .json<{ reason?: string }>()
    .catch((): { reason?: string } => ({}));
  if (shouldDisablePushToken(response.status, failure.reason)) {
    await disableLiveActivityToken(env, activity.token);
  }
  console.log(JSON.stringify({
    level: "error",
    message: "APNs Live Activity update failed",
    activityId: activity.activity_id,
    environment: activity.environment,
    status: response.status,
    reason: failure.reason ?? "Unknown",
  }));
}
async function sendWidgetNotification(
  env: Env,
  authorization: string,
  widget: WidgetPushTokenRow,
) {
  const host = widget.environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const response = await fetch(`${host}/3/device/${widget.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${authorization}`,
      "apns-topic": `${env.APNS_TOPIC}.push-type.widgets`,
      "apns-push-type": "widgets",
      "apns-expiration": "0",
      "apns-collapse-id": "enzo-widget-state",
      "content-type": "application/json",
    },
    body: JSON.stringify(widgetPushPayload()),
  });
  if (response.ok) return;

  const failure = await response
    .json<{ reason?: string }>()
    .catch((): { reason?: string } => ({}));
  if (shouldDisablePushToken(response.status, failure.reason)) {
    await disableWidgetPushToken(env, widget.token);
  }
  console.log(JSON.stringify({
    level: "error",
    message: "APNs WidgetKit update failed",
    environment: widget.environment,
    status: response.status,
    reason: failure.reason ?? "Unknown",
  }));
}


async function sendStateChangeNotification(
  env: Env,
  authorization: string,
  device: PushDeviceRow,
) {
  const host = device.environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  const response = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${authorization}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      aps: { "content-available": 1 },
      enzo: "state-changed",
    }),
  });
  if (response.ok) return;

  const failure = await response
    .json<{ reason?: string }>()
    .catch((): { reason?: string } => ({}));
  if (shouldDisablePushToken(response.status, failure.reason)) {
    await disablePushDevice(env, device.token);
  }
  console.log(JSON.stringify({
    level: "error",
    message: "APNs notification failed",
    environment: device.environment,
    status: response.status,
    reason: failure.reason ?? "Unknown",
  }));
}

async function sendStateChangeNotifications(env: Env) {
  // Allocate before reading D1 so an older snapshot can never carry a newer
  // ActivityKit timestamp than a later state-change job.
  const liveActivityTimestamp = await nextLiveActivityTimestamp(env);
  const [
    { results: devices },
    { results: activities },
    { results: widgets },
    state,
  ] = await Promise.all([
    env.DB.prepare(
      `SELECT token, environment
       FROM push_devices
       WHERE disabled_at IS NULL`,
    ).all<PushDeviceRow>(),
    env.DB.prepare(
      `SELECT token, activity_id, event_id, environment
       FROM live_activity_tokens
       WHERE disabled_at IS NULL`,
    ).all<LiveActivityTokenRow>(),
    env.DB.prepare(
      `SELECT token, environment
       FROM widget_push_tokens
       WHERE disabled_at IS NULL`,
    ).all<WidgetPushTokenRow>(),
    readState(env),
  ]);
  if (devices.length === 0 && activities.length === 0 && widgets.length === 0) return;

  const authorization = await providerToken(env);
  await Promise.all([
    ...devices.map((device) => sendStateChangeNotification(env, authorization, device)),
    ...activities.map((activity) =>
      sendLiveActivityNotification(
        env,
        authorization,
        activity,
        state.nextFeedAt,
        liveActivityTimestamp,
      )
    ),
    ...widgets.map((widget) => sendWidgetNotification(env, authorization, widget)),
  ]);
}

function notifyStateChange(env: Env, ctx: ExecutionContext) {
  ctx.waitUntil(
    sendStateChangeNotifications(env).catch((error) => {
      const message = error instanceof Error ? error.message : "APNs notification failed";
      console.log(JSON.stringify({ level: "error", message }));
    }),
  );
}


async function handleApi(request: Request, url: URL, env: Env, ctx: ExecutionContext) {
  if (request.method === "GET" && url.pathname === "/api/health") {
    const row = await env.DB.prepare("SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now') AS now")
      .first<{ now: string }>();
    return json({ ok: true, storage: "d1", databaseTime: row!.now });
  }

  if (request.method === "GET" && url.pathname === "/api/state") {
    return json(await readState(env));
  }

  if (request.method === "POST" && url.pathname === "/api/push-devices") {
    try {
      const body = await request.json() as Record<string, unknown>;
      const token = typeof body.token === "string" ? body.token.toLowerCase() : "";
      const environment = body.environment;
      if (!/^[0-9a-f]{64}$/.test(token)) {
        throw new Error("token must be a 64-character hexadecimal APNs device token");
      }
      if (environment !== "sandbox" && environment !== "production") {
        throw new Error("environment must be sandbox or production");
      }
      await env.DB.prepare(
        `INSERT INTO push_devices (token, environment)
         VALUES (?1, ?2)
         ON CONFLICT (token) DO UPDATE SET
           environment = excluded.environment,
           disabled_at = NULL,
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      ).bind(token, environment).run();
      return json({ ok: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid push device";
      return json({ ok: false, error: message }, { status: 400 });
    }
  }
  if (request.method === "POST" && url.pathname === "/api/widget-push-devices") {
    try {
      const body = await request.json() as Record<string, unknown>;
      const token = typeof body.token === "string" ? body.token.toLowerCase() : "";
      const environment = body.environment;
      const enabled = body.enabled;
      if (!/^(?:[0-9a-f]{2}){16,128}$/.test(token)) {
        throw new Error("token must be a hexadecimal WidgetKit push token");
      }
      if (environment !== "sandbox" && environment !== "production") {
        throw new Error("environment must be sandbox or production");
      }
      if (typeof enabled !== "boolean") {
        throw new Error("enabled must be a boolean");
      }
      await env.DB.prepare(
        `INSERT INTO widget_push_tokens (token, environment, disabled_at)
         VALUES (
           ?1,
           ?2,
           CASE WHEN ?3 = 1 THEN NULL ELSE strftime('%Y-%m-%dT%H:%M:%fZ', 'now') END
         )
         ON CONFLICT (token) DO UPDATE SET
           environment = excluded.environment,
           disabled_at = excluded.disabled_at,
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
      ).bind(token, environment, enabled ? 1 : 0).run();
      return json({ ok: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid WidgetKit push device";
      return json({ ok: false, error: message }, { status: 400 });
    }
  }


  if (request.method === "POST" && url.pathname === "/api/live-activities") {
    try {
      const body = await request.json() as Record<string, unknown>;
      const token = typeof body.token === "string" ? body.token.toLowerCase() : "";
      const activityID = typeof body.activityID === "string" ? body.activityID.trim() : "";
      const eventID = typeof body.eventID === "string" ? body.eventID.trim() : "";
      const environment = body.environment;
      if (!/^(?:[0-9a-f]{2}){16,128}$/.test(token)) {
        throw new Error("token must be a hexadecimal ActivityKit push token");
      }
      if (!activityID || activityID.length > 128) {
        throw new Error("activityID is required");
      }
      if (!eventID || eventID.length > 128) {
        throw new Error("eventID is required");
      }
      if (environment !== "sandbox" && environment !== "production") {
        throw new Error("environment must be sandbox or production");
      }
      await env.DB.batch([
        env.DB.prepare(
          `UPDATE live_activity_tokens
           SET disabled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
               updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE activity_id = ?1 AND token <> ?2 AND disabled_at IS NULL`,
        ).bind(activityID, token),
        env.DB.prepare(
          `INSERT INTO live_activity_tokens (token, activity_id, event_id, environment)
           VALUES (?1, ?2, ?3, ?4)
           ON CONFLICT (token) DO UPDATE SET
             activity_id = excluded.activity_id,
             event_id = excluded.event_id,
             environment = excluded.environment,
             disabled_at = NULL,
             updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')`,
        ).bind(token, activityID, eventID, environment),
      ]);
      return json({ ok: true });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid Live Activity";
      return json({ ok: false, error: message }, { status: 400 });
    }
  }

  const liveActivityMatch = url.pathname.match(/^\/api\/live-activities\/([^/]+)$/);
  if (request.method === "DELETE" && liveActivityMatch) {
    const activityID = decodeURIComponent(liveActivityMatch[1]!);
    await env.DB.prepare(
      `UPDATE live_activity_tokens
       SET disabled_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE activity_id = ?1 AND disabled_at IS NULL`,
    ).bind(activityID).run();
    return json({ ok: true });
  }

  if (request.method === "POST" && url.pathname === "/api/events") {
    try {
      const event = parseEvent(await request.json() as Record<string, unknown>);
      const result = await env.DB.prepare(
        `INSERT INTO care_events (
           id, occurred_at, type, milk_type, amount_ml, pee, poop, resets_timer, notes
         ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9)
         ON CONFLICT (id) DO NOTHING`,
      ).bind(
        event.id, event.occurredAt, event.type, event.milkType, event.amountMl,
        event.pee ? 1 : 0, event.poop ? 1 : 0, event.resetsTimer ? 1 : 0, event.notes,
      ).run();
      if (result.meta.changes > 0) notifyStateChange(env, ctx);
      return json(
        await mutationResponse(env, event.id),
        { status: result.meta.changes > 0 ? 201 : 200 },
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid event";
      return json({ ok: false, error: message, state: await readState(env) }, { status: 400 });
    }
  }

  const match = url.pathname.match(/^\/api\/events\/([^/]+)$/);
  if (request.method === "PATCH" && match) {
    const id = decodeURIComponent(match[1]!);
    const existing = await env.DB.prepare(
      "SELECT * FROM care_events WHERE id = ?1 AND deleted_at IS NULL LIMIT 1",
    ).bind(id).first<EventRow>();
    if (!existing) return json({ error: "Event not found" }, { status: 404 });
    try {
      const event = parseEvent(
        { ...(await request.json() as Record<string, unknown>), id },
        existing.type,
      );
      await env.DB.prepare(
        `UPDATE care_events SET
           occurred_at = ?1, milk_type = ?2, amount_ml = ?3, pee = ?4, poop = ?5,
           resets_timer = ?6, notes = ?7, updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?8`,
      ).bind(
        event.occurredAt, event.milkType, event.amountMl, event.pee ? 1 : 0,
        event.poop ? 1 : 0, event.resetsTimer ? 1 : 0, event.notes, id,
      ).run();
      notifyStateChange(env, ctx);
      return json(await mutationResponse(env, id));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid update";
      return json({ ok: false, error: message, state: await readState(env) }, { status: 400 });
    }
  }

  if (request.method === "DELETE" && match) {
    const id = decodeURIComponent(match[1]!);
    const result = await env.DB.prepare(
      `UPDATE care_events
       SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE id = ?1 AND deleted_at IS NULL`,
    ).bind(id).run();
    if (result.meta.changes === 0) return json({ error: "Event not found" }, { status: 404 });
    notifyStateChange(env, ctx);
    return json(await mutationResponse(env, id));
  }

  if (
    (request.method === "PUT" || request.method === "PATCH")
    && url.pathname === "/api/profile"
  ) {
    try {
      const body = await request.json() as Record<string, unknown>;
      const hasBirthAt = Object.hasOwn(body, "birthAt");
      const hasFeedInterval = Object.hasOwn(body, "feedIntervalMinutes");
      if (!hasBirthAt && !hasFeedInterval) {
        throw new Error("birthAt or feedIntervalMinutes is required");
      }

      const birthAt = hasBirthAt ? parseOccurredAt(body.birthAt) : null;
      if (birthAt && birthAt > new Date().toISOString()) {
        throw new Error("birthAt must be in the past");
      }

      const feedIntervalMinutes = hasFeedInterval
        ? Number(body.feedIntervalMinutes)
        : null;
      if (
        hasFeedInterval
        && (
          !Number.isInteger(feedIntervalMinutes)
          || feedIntervalMinutes! < 30
          || feedIntervalMinutes! > 720
        )
      ) {
        throw new Error("feedIntervalMinutes must be between 30 and 720");
      }

      if (birthAt && feedIntervalMinutes !== null) {
        await env.DB.prepare(
          `UPDATE profile SET
             birth_at = ?1,
             feed_interval_minutes = ?2,
             updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE id = 1`,
        ).bind(birthAt, feedIntervalMinutes).run();
      } else if (birthAt) {
        await env.DB.prepare(
          `UPDATE profile SET
             birth_at = ?1,
             updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE id = 1`,
        ).bind(birthAt).run();
      } else {
        await env.DB.prepare(
          `UPDATE profile SET
             feed_interval_minutes = ?1,
             updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
           WHERE id = 1`,
        ).bind(feedIntervalMinutes).run();
      }
      notifyStateChange(env, ctx);
      return json({ ok: true, state: await readState(env) });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid profile";
      return json({ ok: false, error: message, state: await readState(env) }, { status: 400 });
    }
  }

  const checkupColumns = CHECKUP_FIELDS.map(([column]) => column);
  if (request.method === "POST" && url.pathname === "/api/checkups") {
    try {
      const checkup = parseCheckup(await request.json() as Record<string, unknown>);
      const values = CHECKUP_FIELDS.map(([, key]) => checkup[key]);
      const placeholders = values.map((_, i) => `?${i + 4}`).join(", ");
      const result = await env.DB.prepare(
        `INSERT INTO checkups (id, occurred_at, notes, ${checkupColumns.join(", ")})
         VALUES (?1, ?2, ?3, ${placeholders})
         ON CONFLICT (id) DO NOTHING`,
      ).bind(checkup.id, checkup.occurredAt, checkup.notes, ...values).run();
      if (result.meta.changes > 0) notifyStateChange(env, ctx);
      return json(
        { ok: true, checkupId: checkup.id, state: await readState(env) },
        { status: result.meta.changes > 0 ? 201 : 200 },
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid checkup";
      return json({ ok: false, error: message, state: await readState(env) }, { status: 400 });
    }
  }

  const checkupMatch = url.pathname.match(/^\/api\/checkups\/([^/]+)$/);
  if (request.method === "PATCH" && checkupMatch) {
    const id = decodeURIComponent(checkupMatch[1]!);
    const existing = await env.DB.prepare(
      "SELECT id FROM checkups WHERE id = ?1 AND deleted_at IS NULL LIMIT 1",
    ).bind(id).first<{ id: string }>();
    if (!existing) return json({ error: "Checkup not found" }, { status: 404 });
    try {
      const checkup = parseCheckup({ ...(await request.json() as Record<string, unknown>), id });
      const values = CHECKUP_FIELDS.map(([, key]) => checkup[key]);
      const assignments = checkupColumns.map((column, i) => `${column} = ?${i + 4}`).join(", ");
      await env.DB.prepare(
        `UPDATE checkups SET occurred_at = ?2, notes = ?3, ${assignments},
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
         WHERE id = ?1`,
      ).bind(id, checkup.occurredAt, checkup.notes, ...values).run();
      notifyStateChange(env, ctx);
      return json({ ok: true, checkupId: id, state: await readState(env) });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid checkup";
      return json({ ok: false, error: message, state: await readState(env) }, { status: 400 });
    }
  }

  if (request.method === "DELETE" && checkupMatch) {
    const id = decodeURIComponent(checkupMatch[1]!);
    const result = await env.DB.prepare(
      `UPDATE checkups
       SET deleted_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
           updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
       WHERE id = ?1 AND deleted_at IS NULL`,
    ).bind(id).run();
    if (result.meta.changes === 0) return json({ error: "Checkup not found" }, { status: 404 });
    notifyStateChange(env, ctx);
    return json({ ok: true, checkupId: id, state: await readState(env) });
  }

  return json({ error: "Not found" }, { status: 404 });
}

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api/")) {
      return new Response("Not found", { status: 404 });
    }
    if (!authorized(request, env)) {
      return json({ error: "Unauthorized" }, { status: 401 });
    }
    try {
      return await handleApi(request, url, env, ctx);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Database error";
      console.log(JSON.stringify({ level: "error", message }));
      return json({ ok: false, error: message }, { status: 500 });
    }
  },
} satisfies ExportedHandler<Env>;

/**
 * Local Enzo API. Postgres is the durable source of truth. The legacy Google
 * Sheets tracker is supported only as a one-time, read-only import.
 */
import { join } from "node:path";
import { syncLegacyMutation } from "./legacy-sync";

type EventType = "feed" | "diaper";

type EventRow = {
  id: string;
  occurred_at: Date | string;
  type: EventType;
  milk_type: "formula" | "breast-milk" | null;
  amount_ml: number | string | null;
  pee: boolean;
  poop: boolean;
  resets_timer: boolean;
  notes: string;
  source: string;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
};

const port = Number(process.env.ENZO_PROTOTYPE_PORT ?? 4318);
const hostname = process.env.ENZO_PROTOTYPE_HOST ?? "127.0.0.1";
const timezone = process.env.ENZO_TIMEZONE ?? "America/Phoenix";
const intervalMinutes = Number(process.env.ENZO_INTERVAL_MINUTES ?? 180);
const databaseURL = process.env.DATABASE_URL ?? "postgresql://localhost/enzo";

if (!Number.isFinite(port) || !Number.isFinite(intervalMinutes)) {
  throw new Error("ENZO_PROTOTYPE_PORT and ENZO_INTERVAL_MINUTES must be numbers");
}

const sql = new Bun.SQL(databaseURL, { max: 10 });

await sql`
  CREATE TABLE IF NOT EXISTS care_events (
    id text PRIMARY KEY,
    occurred_at timestamptz NOT NULL,
    type text NOT NULL CHECK (type IN ('feed', 'diaper')),
    milk_type text CHECK (milk_type IS NULL OR milk_type IN ('formula', 'breast-milk')),
    amount_ml numeric CHECK (amount_ml IS NULL OR (amount_ml >= 0 AND amount_ml <= 1000)),
    pee boolean NOT NULL DEFAULT false,
    poop boolean NOT NULL DEFAULT false,
    resets_timer boolean NOT NULL DEFAULT true,
    notes text NOT NULL DEFAULT '',
    source text NOT NULL DEFAULT 'app',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz,
    CHECK (
      (type = 'feed' AND milk_type IS NOT NULL AND pee = false AND poop = false)
      OR
      (type = 'diaper' AND milk_type IS NULL AND amount_ml IS NULL AND (pee OR poop))
    )
  )
`;
await sql`CREATE INDEX IF NOT EXISTS care_events_occurred_at_idx ON care_events (occurred_at DESC) WHERE deleted_at IS NULL`;

function json(value: unknown, init: ResponseInit = {}) {
  const headers = new Headers(init.headers);
  headers.set("content-type", "application/json; charset=utf-8");
  headers.set("cache-control", "no-store");
  return new Response(JSON.stringify(value), { ...init, headers });
}

function asISO(value: Date | string) {
  return (value instanceof Date ? value : new Date(value)).toISOString();
}

function localDay(value: Date | string) {
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
    occurredAt: asISO(row.occurred_at),
    notes: row.notes,
  };
  if (row.type === "feed") {
    return {
      ...base,
      type: "feed" as const,
      feed: {
        milkType: row.milk_type!,
        amountMl: row.amount_ml === null ? null : Number(row.amount_ml),
        resetsTimer: row.resets_timer,
      },
    };
  }
  return {
    ...base,
    type: "diaper" as const,
    diaper: { pee: row.pee, poop: row.poop },
  };
}

async function activeEvents() {
  return await sql<EventRow[]>`
    SELECT * FROM care_events
    WHERE deleted_at IS NULL
    ORDER BY occurred_at DESC, created_at DESC
  `;
}

async function readState() {
  const rows = await activeEvents();
  const today = localDay(new Date());
  const todayRows = rows.filter((row) => localDay(row.occurred_at) === today);
  const lastResettingFeed = rows.find((row) => row.type === "feed" && row.resets_timer);
  const lastFeed = rows.find((row) => row.type === "feed");
  const nextFeedAt = lastResettingFeed
    ? new Date(new Date(lastResettingFeed.occurred_at).getTime() + intervalMinutes * 60_000).toISOString()
    : null;

  return {
    prototype: true,
    storage: "postgres",
    timezone,
    intervalMinutes,
    now: new Date().toISOString(),
    nextFeedAt,
    lastFeed: lastFeed ? serializeEvent(lastFeed) : null,
    today: {
      milkMl: todayRows.reduce((sum, row) => sum + Number(row.amount_ml ?? 0), 0),
      feeds: todayRows.filter((row) => row.type === "feed").length,
      pees: todayRows.filter((row) => row.pee).length,
      poops: todayRows.filter((row) => row.poop).length,
    },
    events: rows.map(serializeEvent),
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
    const feed = isRecord(body.feed) ? body.feed : body;
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
    const diaper = isRecord(body.diaper) ? body.diaper : body;
    event.pee = diaper.pee === true;
    event.poop = diaper.poop === true;
    event.resetsTimer = false;
    if (!event.pee && !event.poop) throw new Error("a diaper needs pee, poop, or both");
  }
  return event;
}

async function mutationResponse(
  eventId: string,
  operation: "upsert" | "delete",
  eventType: EventType,
) {
  const state = await readState();
  const event = operation === "upsert"
    ? state.events.find((candidate) => candidate.id === eventId)
    : undefined;
  const legacySync = await syncLegacyMutation({
    operation,
    eventID: eventId,
    event,
    updateReminder: eventType === "feed" && state.nextFeedAt !== null,
    nextFeedAt: state.nextFeedAt,
  });
  return { ok: true, eventId, legacySync, state };
}

async function handleApi(request: Request, url: URL) {
  if (request.method === "GET" && url.pathname === "/api/health") {
    const [{ now }] = await sql<{ now: Date }[]>`SELECT now()`;
    return json({ ok: true, storage: "postgres", databaseTime: now.toISOString() });
  }

  if (request.method === "GET" && url.pathname === "/api/state") {
    return json(await readState());
  }

  if (request.method === "POST" && url.pathname === "/api/events") {
    try {
      const event = parseEvent(await request.json() as Record<string, unknown>);
      const inserted = await sql<{ id: string }[]>`
        INSERT INTO care_events (
          id, occurred_at, type, milk_type, amount_ml, pee, poop, resets_timer, notes
        ) VALUES (
          ${event.id}, ${event.occurredAt}, ${event.type}, ${event.milkType}, ${event.amountMl},
          ${event.pee}, ${event.poop}, ${event.resetsTimer}, ${event.notes}
        )
        ON CONFLICT (id) DO NOTHING
        RETURNING id
      `;
      return json(
        await mutationResponse(event.id, "upsert", event.type),
        { status: inserted.length > 0 ? 201 : 200 },
      );
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid event";
      return json({ ok: false, error: message, state: await readState() }, { status: 400 });
    }
  }

  const match = url.pathname.match(/^\/api\/events\/([^/]+)$/);
  if (request.method === "PATCH" && match) {
    const id = decodeURIComponent(match[1]!);
    const [existing] = await sql<EventRow[]>`
      SELECT * FROM care_events WHERE id = ${id} AND deleted_at IS NULL LIMIT 1
    `;
    if (!existing) return json({ error: "Event not found" }, { status: 404 });
    try {
      const event = parseEvent({ ...(await request.json() as Record<string, unknown>), id }, existing.type);
      await sql`
        UPDATE care_events SET
          occurred_at = ${event.occurredAt}, milk_type = ${event.milkType},
          amount_ml = ${event.amountMl}, pee = ${event.pee}, poop = ${event.poop},
          resets_timer = ${event.resetsTimer}, notes = ${event.notes}, updated_at = now()
        WHERE id = ${id}
      `;
      return json(await mutationResponse(id, "upsert", existing.type));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Invalid update";
      return json({ ok: false, error: message, state: await readState() }, { status: 400 });
    }
  }

  if (request.method === "DELETE" && match) {
    const id = decodeURIComponent(match[1]!);
    const deleted = await sql<{ type: EventType }[]>`
      UPDATE care_events SET deleted_at = now(), updated_at = now()
      WHERE id = ${id} AND deleted_at IS NULL
      RETURNING type
    `;
    if (!deleted.length) return json({ error: "Event not found" }, { status: 404 });
    return json(await mutationResponse(id, "delete", deleted[0]!.type));
  }

  return json({ error: "Not found" }, { status: 404 });
}

const server = Bun.serve({
  port,
  hostname,
  async fetch(request) {
    const url = new URL(request.url);
    if (url.pathname.startsWith("/api/")) {
      try {
        return await handleApi(request, url);
      } catch (error) {
        const message = error instanceof Error ? error.message : "Database error";
        return json({ ok: false, error: message }, { status: 500 });
      }
    }
    if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      return new Response(Bun.file(join(import.meta.dir, "index.html")), {
        headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" },
      });
    }
    return new Response("Not found", { status: 404 });
  },
});

console.log(`Enzo server: http://${server.hostname}:${server.port}`);
console.log(`Storage: Postgres (${new URL(databaseURL).pathname.slice(1)})`);

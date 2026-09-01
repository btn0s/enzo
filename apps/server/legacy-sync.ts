import { resolve } from "node:path";

export type LegacySyncEnvelope = {
  operation: "upsert" | "delete";
  eventID: string;
  event?: unknown;
  updateReminder: boolean;
  nextFeedAt: string | null;
};

export type LegacySyncResult = {
  ok: boolean;
  attempts: number;
  error?: string;
};

type ExecuteSync = (envelope: LegacySyncEnvelope) => Promise<void>;
type Sleep = (milliseconds: number) => Promise<void>;

const legacyRoot = resolve(import.meta.dir, "../../legacy/sheets-reminders");
const legacyCLI = resolve(legacyRoot, "bin/enzo");

async function executeLegacyCLI(envelope: LegacySyncEnvelope) {
  const child = Bun.spawn([legacyCLI, "sync-event"], {
    cwd: legacyRoot,
    env: Bun.env,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  child.stdin.write(JSON.stringify(envelope));
  child.stdin.end();

  const [exitCode, stderr] = await Promise.all([
    child.exited,
    new Response(child.stderr).text(),
  ]);
  if (exitCode !== 0) {
    throw new Error(stderr.trim() || `Legacy CLI exited ${exitCode}`);
  }
}

export async function syncLegacyMutation(
  envelope: LegacySyncEnvelope,
  options: {
    execute?: ExecuteSync;
    sleep?: Sleep;
    attempts?: number;
  } = {},
): Promise<LegacySyncResult> {
  const execute = options.execute ?? executeLegacyCLI;
  const sleep = options.sleep ?? ((milliseconds) => Bun.sleep(milliseconds));
  const attempts = options.attempts ?? Number(process.env.ENZO_LEGACY_SYNC_ATTEMPTS ?? 3);
  if (!Number.isInteger(attempts) || attempts < 1) {
    return { ok: false, attempts: 0, error: "ENZO_LEGACY_SYNC_ATTEMPTS must be a positive integer" };
  }

  let lastError = "Unknown legacy sync failure";
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    try {
      await execute(envelope);
      return { ok: true, attempts: attempt };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      if (attempt < attempts) await sleep(Math.min(2 ** (attempt - 1), 4) * 1000);
    }
  }
  return { ok: false, attempts, error: lastError };
}

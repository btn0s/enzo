/** One-time, read-only migration from a Google Sheets CSV export to Postgres. */
import { basename } from "node:path";

const csvPath = process.argv[2];
if (!csvPath) throw new Error("Usage: bun apps/server/import-tracker.ts /path/to/tracker.csv");

const databaseURL = process.env.DATABASE_URL ?? "postgresql://localhost/enzo";
const sql = new Bun.SQL(databaseURL);
const text = await Bun.file(csvPath).text();

function parseCSV(input: string) {
  const rows: string[][] = [];
  let row: string[] = [];
  let cell = "";
  let quoted = false;
  for (let index = 0; index < input.length; index += 1) {
    const character = input[index]!;
    if (quoted) {
      if (character === '"' && input[index + 1] === '"') {
        cell += '"';
        index += 1;
      } else if (character === '"') {
        quoted = false;
      } else {
        cell += character;
      }
    } else if (character === '"') {
      quoted = true;
    } else if (character === ",") {
      row.push(cell);
      cell = "";
    } else if (character === "\n") {
      row.push(cell.replace(/\r$/, ""));
      rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += character;
    }
  }
  if (cell || row.length) {
    row.push(cell.replace(/\r$/, ""));
    rows.push(row);
  }
  return rows;
}

const months = new Map([
  ["Jan", 0], ["Feb", 1], ["Mar", 2], ["Apr", 3], ["May", 4], ["Jun", 5],
  ["Jul", 6], ["Aug", 7], ["Sep", 8], ["Oct", 9], ["Nov", 10], ["Dec", 11],
]);

function occurredAt(dateText: string, timeText: string, cameFromAPI: boolean) {
  const dateMatch = dateText.match(/^(\w{3}) (\d{1,2}), (\d{4})$/);
  const timeMatch = timeText.match(/^(\d{1,2}):(\d{2}) (AM|PM)$/i);
  if (!dateMatch || !timeMatch) throw new Error(`Invalid tracker timestamp: ${dateText} ${timeText}`);
  const month = months.get(dateMatch[1]!);
  if (month === undefined) throw new Error(`Invalid tracker month: ${dateMatch[1]}`);
  let hour = Number(timeMatch[1]);
  if (timeMatch[3]!.toUpperCase() === "PM" && hour < 12) hour += 12;
  if (timeMatch[3]!.toUpperCase() === "AM" && hour === 12) hour = 0;
  const year = Number(dateMatch[3]);
  const day = Number(dateMatch[2]);

  // The legacy Sheet is UTC. API-written rows contain an ID and therefore show
  // seven hours ahead of Phoenix; paper/browser backfill rows are local wall time.
  if (cameFromAPI) return new Date(Date.UTC(year, month, day, hour, Number(timeMatch[2]))).toISOString();
  const offset = "-07:00";
  return new Date(
    `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}` +
    `T${String(hour).padStart(2, "0")}:${timeMatch[2]}:00${offset}`,
  ).toISOString();
}

const rows = parseCSV(text);
const header = rows.shift()?.map((value) => value.trim()) ?? [];
const expected = ["Date", "Time", "Event", "Milk Type", "Amount (mL)", "Details (optional)", "Notes", "Event ID"];
if (expected.some((value, index) => header[index] !== value)) {
  throw new Error(`Unexpected CSV headers in ${basename(csvPath)}: ${header.join(", ")}`);
}

let inserted = 0;
let skipped = 0;
for (const [index, cells] of rows.entries()) {
  if (cells.every((cell) => !cell.trim())) continue;
  const [date, time, eventName, milkName, amountText, details, notes, sheetID] = cells;
  if (!date || !time || !eventName) {
    skipped += 1;
    continue;
  }
  const isFeed = eventName === "Eating";
  const pee = eventName === "Pee" || eventName === "Pee + Poop";
  const poop = eventName === "Poop" || eventName === "Pee + Poop";
  if (!isFeed && !pee && !poop) throw new Error(`Unknown event on CSV row ${index + 2}: ${eventName}`);
  const timestamp = occurredAt(date, time, Boolean(sheetID));
  const fallbackKey = [date, time, eventName, milkName, amountText, details, notes, index].join("\u001f");
  const hash = new Bun.CryptoHasher("sha256").update(fallbackKey).digest("hex");
  const id = sheetID?.trim() || `sheet-${hash.slice(0, 32)}`;
  const milkType = isFeed ? (milkName === "Breast milk" ? "breast-milk" : "formula") : null;
  const amount = isFeed && amountText?.trim() ? Number(amountText) : null;
  const combinedNotes = [details?.trim(), notes?.trim()].filter(Boolean).join(" — ");

  const result = await sql<{ id: string }[]>`
    INSERT INTO care_events (
      id, occurred_at, type, milk_type, amount_ml, pee, poop, resets_timer, notes, source
    ) VALUES (
      ${id}, ${timestamp}, ${isFeed ? "feed" : "diaper"}, ${milkType}, ${amount},
      ${pee}, ${poop}, ${isFeed}, ${combinedNotes}, 'sheet-import'
    )
    ON CONFLICT (id) DO NOTHING
    RETURNING id
  `;
  if (result.length) inserted += 1;
  else skipped += 1;
}

const [{ count }] = await sql<{ count: string }[]>`SELECT count(*)::text AS count FROM care_events WHERE deleted_at IS NULL`;
console.log(JSON.stringify({ ok: true, inserted, skipped, total: Number(count) }, null, 2));
await sql.close();

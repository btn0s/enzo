const DEFAULT_TRACKER_SHEET = 'Tracker';
const DEFAULT_FEED_INTERVAL_MINUTES = 180;
const EVENT_ID_COLUMN = 8;
const ALLOWED_EVENTS = new Set(['Eating', 'Pee', 'Poop', 'Pee + Poop']);
const ALLOWED_MILK = new Set(['', 'Formula', 'Breast milk']);

function configureBoundSpreadsheet() {
  const spreadsheet = SpreadsheetApp.getActiveSpreadsheet();
  if (!spreadsheet) throw new Error('Run this function from a spreadsheet-bound Apps Script project');
  PropertiesService.getScriptProperties().setProperty('ENZO_SHEET_ID', spreadsheet.getId());
  return 'ENZO_SHEET_ID configured';
}

function doPost(e) {
  try {
    const request = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    requireToken_(request.token);
    if (request.action === 'log') return json_(logEvent_(request));
    if (request.action === 'update_feed') return json_(updateLatestFeed_(request));
    if (request.action === 'status') return json_({ok: true, status: status_()});
    throw new Error('Unknown action');
  } catch (error) {
    return json_({ok: false, error: String(error.message || error)});
  }
}

function requireToken_(provided) {
  const expected = PropertiesService.getScriptProperties().getProperty('ENZO_API_TOKEN');
  if (!expected) throw new Error('ENZO_API_TOKEN is not configured');
  if (!provided || provided !== expected) throw new Error('Unauthorized');
}

function property_(name, options) {
  const value = PropertiesService.getScriptProperties().getProperty(name);
  if (value) return value;
  if (options && Object.prototype.hasOwnProperty.call(options, 'defaultValue')) {
    return options.defaultValue;
  }
  throw new Error(`${name} is not configured`);
}

function tracker_() {
  const sheetId = property_('ENZO_SHEET_ID');
  const sheetName = property_('ENZO_TRACKER_SHEET', {defaultValue: DEFAULT_TRACKER_SHEET});
  const sheet = SpreadsheetApp.openById(sheetId).getSheetByName(sheetName);
  if (!sheet) throw new Error(`Sheet not found: ${sheetName}`);
  if (sheet.getRange(1, EVENT_ID_COLUMN).getValue() !== 'Event ID') {
    sheet.getRange(1, EVENT_ID_COLUMN).setValue('Event ID');
    sheet.hideColumns(EVENT_ID_COLUMN);
  }
  return sheet;
}

function logEvent_(request) {
  validate_(request);
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = tracker_();
    const lastRow = sheet.getLastRow();
    if (lastRow > 1) {
      const ids = sheet.getRange(2, EVENT_ID_COLUMN, lastRow - 1, 1).getDisplayValues().flat();
      const existingIndex = ids.indexOf(request.id);
      if (existingIndex >= 0) {
        return {ok: true, duplicate: true, row: existingIndex + 2, id: request.id};
      }
    }

    const occurredAt = new Date(request.occurred_at);
    const row = sheet.getLastRow() + 1;
    const values = [[
      occurredAt,
      occurredAt,
      request.event,
      request.milk_type || '',
      request.amount_ml === null || request.amount_ml === '' ? '' : Number(request.amount_ml),
      request.details || '',
      request.notes || '',
      request.id,
    ]];
    sheet.getRange(row, 1, 1, EVENT_ID_COLUMN).setValues(values);
    sheet.getRange(row, 1).setNumberFormat('mmm d, yyyy');
    sheet.getRange(row, 2).setNumberFormat('h:mm AM/PM');
    if (sheet.getLastRow() > 2) {
      sheet.getRange(2, 1, sheet.getLastRow() - 1, EVENT_ID_COLUMN).sort([
        {column: 1, ascending: true},
        {column: 2, ascending: true},
      ]);
    }
    SpreadsheetApp.flush();
    return {ok: true, duplicate: false, id: request.id};
  } finally {
    lock.releaseLock();
  }
}

function validate_(request) {
  if (!request.id || typeof request.id !== 'string') throw new Error('id is required');
  if (!ALLOWED_EVENTS.has(request.event)) throw new Error('Invalid event');
  if (!ALLOWED_MILK.has(request.milk_type || '')) throw new Error('Invalid milk type');
  if (request.event === 'Eating' && !request.milk_type) throw new Error('Milk type is required for Eating');
  if (request.event !== 'Eating' && request.milk_type) throw new Error('Milk type is only valid for Eating');
  if (Number.isNaN(new Date(request.occurred_at).getTime())) throw new Error('Invalid occurred_at');
  if (request.amount_ml !== null && request.amount_ml !== '' && Number(request.amount_ml) < 0) {
    throw new Error('Amount must be zero or greater');
  }
}

function updateLatestFeed_(request) {
  if (request.amount_ml === null || request.amount_ml === '' || Number(request.amount_ml) < 0) {
    throw new Error('A non-negative amount_ml is required');
  }
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const sheet = tracker_();
    const lastRow = sheet.getLastRow();
    if (lastRow < 2) throw new Error('No feeding row exists');
    const values = sheet.getRange(2, 1, lastRow - 1, 7).getValues();
    for (let index = values.length - 1; index >= 0; index -= 1) {
      if (values[index][2] !== 'Eating') continue;
      const row = index + 2;
      sheet.getRange(row, 5).setValue(Number(request.amount_ml));
      if (request.details !== null && request.details !== undefined) {
        sheet.getRange(row, 6).setValue(request.details);
      }
      if (request.notes !== null && request.notes !== undefined) {
        sheet.getRange(row, 7).setValue(request.notes);
      }
      const occurredAt = new Date(values[index][0]);
      const time = new Date(values[index][1]);
      occurredAt.setHours(time.getHours(), time.getMinutes(), time.getSeconds(), 0);
      SpreadsheetApp.flush();
      return {ok: true, row, occurred_at: occurredAt.toISOString()};
    }
    throw new Error('No feeding row exists');
  } finally {
    lock.releaseLock();
  }
}

function status_() {
  const sheet = tracker_();
  const lastRow = sheet.getLastRow();
  if (lastRow < 2) return {row_count: 0, last_feed_at: null, next_feed_at: null};
  const values = sheet.getRange(2, 1, lastRow - 1, 5).getValues();
  let lastFeed = null;
  values.forEach(row => {
    if (row[2] !== 'Eating') return;
    const date = new Date(row[0]);
    const time = new Date(row[1]);
    date.setHours(time.getHours(), time.getMinutes(), time.getSeconds(), 0);
    if (!lastFeed || date > lastFeed) lastFeed = date;
  });
  const intervalMinutes = Number(property_('ENZO_FEED_INTERVAL_MINUTES', {
    defaultValue: String(DEFAULT_FEED_INTERVAL_MINUTES),
  }));
  if (!Number.isFinite(intervalMinutes) || intervalMinutes <= 0) {
    throw new Error('ENZO_FEED_INTERVAL_MINUTES must be a positive number');
  }
  return {
    row_count: values.length,
    last_feed_at: lastFeed ? lastFeed.toISOString() : null,
    next_feed_at: lastFeed ? new Date(lastFeed.getTime() + intervalMinutes * 60000).toISOString() : null,
  };
}

function json_(value) {
  return ContentService.createTextOutput(JSON.stringify(value))
    .setMimeType(ContentService.MimeType.JSON);
}

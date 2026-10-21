const BASE_HEADERS = ["Session ID", "Status", "Started (Katowice)", "Ended (Katowice)", "Mode", "Role", "Players", "Minutes", "Start stats", "End stats", "Full report"];
const SESSION_HEADERS = BASE_HEADERS.concat([
  "Start day", "End day", "Start money", "End money", "Start cups", "End cups", "Cups this session",
  "Demo at start", "Demo at end", "Happy (final day)", "Unhappy/lost (final day)", "Discoveries", "Perfect recipes",
  "Menu wishlist clicks", "Completion wishlist clicks", "Discord clicks", "Average FPS", "Below 30 FPS (%)",
  "GPU", "CPU", "RAM (GB)", "Resolution", "Renderer", "Achievements", "Exit reason",
  "Match ID", "Data version", "Peak connected", "Participant connections", "Stand", "Last received (Katowice)",
  "Revision", "Steam build", "Demo screen seen", "FPS sample seconds", "Graphics preset",
  "Main menu wishlist clicks", "Pause menu wishlist clicks", "Main menu Discord clicks", "Pause menu Discord clicks"
]);
const MATCH_HEADERS = ["Match ID", "Status", "Mode", "Peak connected", "Participant connections", "Minutes", "Steam build", "Stands", "Cups this match", "Happy buyers", "Timeouts", "Price rejections", "Wrong orders", "Scams", "Unhappy buyers", "Completed stands", "Sales revenue", "Spending", "Last received (Katowice)", "Revision"];
const STAND_HEADERS = ["Match / stand", "Match ID", "Stand", "Mode", "Status", "Start day", "Latest day", "Start money", "Latest money", "Cups this match", "Happy buyers", "Timeouts", "Price rejections", "Wrong orders", "Scams", "Fruit complaints", "Sugar complaints", "Ice complaints", "Buyers", "Arrivals", "Sales revenue", "Spending", "Demo at start", "Demo latest", "First cup (seconds)", "First sale (seconds)", "Recipe discovered (seconds)", "Demo completed (seconds)", "Last received (Katowice)"];

const TUTORIAL_HEADERS = ["Match / stand / step", "Match ID", "Stand", "Step ID", "Step order", "Step", "Status", "Started (match seconds)", "Completed (match seconds)", "Elapsed seconds", "Active seconds", "Already satisfied", "Resumed partial step", "Last received (Katowice)", "Revision", "Steam build"];
const BATCH_HEADERS = ["Match / batch", "Match ID", "Stand", "Batch ID", "Pitcher batch", "Batch of this fruit", "Fruit", "Fruit amount", "Water", "Sugar", "Ice", "Carried in / unattributed", "Recipe known at pour", "Started (match seconds)", "Day", "Cups poured", "Customer cups tasted", "Customer tasters", "Happy tasters", "Unhappy tasters", "Sugar complaints", "Ice complaints", "Fruit complaints", "Too sweet", "Not sweet enough", "Too cold", "Not cold enough", "Too strong", "Not enough fruit", "Free sample cups", "Free sample tasters", "Happy samples", "Unhappy samples", "Sample sugar complaints", "Sample ice complaints", "Sample fruit complaints", "Min tasting temperature", "Max tasting temperature", "Last received (Katowice)", "Revision", "Steam build"];

function setupTelemetry() {
  const props = PropertiesService.getScriptProperties();
  if (!props.getProperty("SHEET_ID")) props.setProperty("SHEET_ID", SpreadsheetApp.getActiveSpreadsheet().getId());
  if (!props.getProperty("READ_KEY")) props.setProperty("READ_KEY", Utilities.getUuid() + Utilities.getUuid());
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    const book = getBook();
    book.setSpreadsheetTimeZone("Europe/Warsaw");
    const sessions = ensureTab(book, "Sessions", SESSION_HEADERS);
    ensureTab(book, "Matches", MATCH_HEADERS);
    ensureTab(book, "Stands", STAND_HEADERS);
    ensureTab(book, "Tutorial Steps", TUTORIAL_HEADERS);
    ensureTab(book, "Pitcher Batches", BATCH_HEADERS);
    const count = sessions.getLastRow() - 1;
    if (count > 0) {
      const rows = sessions.getRange(2, 1, count, BASE_HEADERS.length).getValues();
      rows.forEach((row, index) => {
        let p;
        try { p = JSON.parse(row[10]); } catch (_) { return; }
        if (!p || !p.session_id) return;
        sessions.getRange(index + 2, 1, 1, SESSION_HEADERS.length).setValues([sessionRow(p, row)]);
      });
    }
    localDateColumns(sessions, [3, 4, 42]);
    localDateColumns(book.getSheetByName("Matches"), [19]);
    localDateColumns(book.getSheetByName("Stands"), [29]);
    sessions.hideColumns(9, 3);
    buildOverview(book);
    buildPreview(book);
    layoutOverview();
    refreshLearningCharts(book);
  } finally {
    lock.releaseLock();
  }
}

function doPost(e) {
  try {
    const raw = e && e.postData ? e.postData.contents : "";
    if (!raw || raw.length > 48000) return reply({ok: false, error: "Invalid request size"});
    const p = JSON.parse(raw);
    if (!p || typeof p !== "object" || Array.isArray(p)) return reply({ok: false, error: "Invalid payload"});
    const props = PropertiesService.getScriptProperties();
    if (p.action === "read") {
      const key = props.getProperty("READ_KEY");
      if (!key || p.read_key !== key) return reply({ok: false, error: "Unauthorized"});
      return readRows(p);
    }
    if (!/^[a-zA-Z0-9_-]{8,80}$/.test(String(p.session_id || ""))) return reply({ok: false, error: "Invalid session ID"});
    if (!["session_start", "checkpoint", "session_end", "learning"].includes(p.event)) return reply({ok: false, error: "Invalid event"});
    const lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      const book = getBook();
      if (p.event === "learning") return ingestLearning(book, p);
      const sessions = book.getSheetByName("Sessions");
      const rowNumber = findRow(sessions, p.session_id);
      const old = rowNumber ? sessions.getRange(rowNumber, 1, 1, SESSION_HEADERS.length).getValues()[0] : [];
      let previous = {};
      try { previous = JSON.parse(old[10] || "{}"); } catch (_) {}
      if (old[1] === "Ended" && p.event !== "session_end") return reply({ok: true, ignored: "Ended already"});
      if (p.schema_version === 2 && previous.schema_version === 2 && number(p.revision) <= number(previous.revision)) return reply({ok: true, ignored: "Stale revision"});
      const now = new Date();
      const row = sessionRow(p, old, now);
      writeRow(sessions, rowNumber || sessions.getLastRow() + 1, row);
      if (p.schema_version === 2 && p.role === "host" && /^[a-zA-Z0-9_-]{8,80}$/.test(String(p.match_id || ""))) {
        updateMatch(book, p, now);
        // Session payloads may carry embedded learning records (tutorial /
        // pitcher rows bundled into checkpoints and the quit summary so the
        // short exit flush needs fewer requests). Ingest them here and tell
        // the sender they were accepted so it can drop its queued copies.
        if (Array.isArray(p.records) && p.records.length) {
          const err = writeLearningRecords(book, p, now);
          if (err) return reply({ok: false, error: err});
          return reply({ok: true, records_accepted: true});
        }
      }
      return reply({ok: true});
    } finally {
      lock.releaseLock();
    }
  } catch (_) {
    return reply({ok: false, error: "Request failed"});
  }
}

function sessionRow(p, old, now) {
  const start = p.start || {};
  const end = p.end || {};
  const hardware = p.hardware || {};
  const clicks = p.clicks || {};
  const final = p.event === "session_end";
  const version = p.schema_version === 2 ? "v2" : "legacy";
  const status = final ? "Ended" : "No end received";
  const started = old[2] || timestamp(p.started_utc) || (p.event === "session_start" || version === "v2" && Object.keys(start).length ? now || "" : "");
  const ended = old[3] || (final ? timestamp(p.ended_utc) || now || "" : "");
  const values = [
    p.session_id, status, started, ended, p.mode, p.role, p.players, final ? p.minutes : "",
    JSON.stringify(start), final ? JSON.stringify(end) : "", JSON.stringify(p),
    start.day, end.day, start.money, end.money, start.cups, end.cups, difference(end.cups, start.cups),
    start.demo, end.demo, end.happy_today, end.lost_today, end.discoveries, end.perfect_recipes,
    clicks.wishlist_menu, clicks.wishlist_complete, clicks.discord, p.avg_fps, p.low_fps_percent,
    hardware.gpu, hardware.cpu, hardware.ram_gb, hardware.resolution, hardware.renderer, p.achievements, final ? p.reason : "",
    p.match_id, version, p.players, p.participants, (p.latest || end || start).stand_id, now || old[41] || "",
    p.revision, p.steam_build, clicks.demo_screen_seen, p.fps_sample_seconds, hardware.graphics_quality,
    clicks.wishlist_main_menu, clicks.wishlist_pause, clicks.discord_main_menu, clicks.discord_pause
  ];
  [2, 3, 41].forEach(index => values[index] = timestamp(values[index]));
  return values.map(cell);
}

function updateMatch(book, p, now) {
  const reports = Array.isArray(p.stand_reports) ? p.stand_reports.slice(0, 4) : [];
  const aggregate = {cups: 0, happy: 0, timeouts: 0, too_expensive: 0, wrong_order: 0, scams: 0, unhappy: 0, completed: 0, revenue: 0, spending: 0};
  const status = p.event === "session_end" ? "Ended" : "No end received";
  const stands = book.getSheetByName("Stands");
  reports.forEach(report => {
    const start = report.start || {};
    const last = report.latest || {};
    const times = report.milestones || {};
    const before = start.outcomes || {};
    const after = last.outcomes || {};
    const outcome = key => number(after[key]) - number(before[key]);
    const cups = number(last.cups) - number(start.cups);
    const revenue = number(last.revenue) - number(start.revenue);
    const spending = number(last.spending) - number(start.spending);
    const row = [p.match_id + ":" + report.stand_id, p.match_id, report.stand_id, p.mode, status,
      start.day, last.day, start.money, last.money, cups, outcome("happy"), outcome("timeouts"), outcome("too_expensive"), outcome("wrong_order"), outcome("scams"),
      outcome("complaints_fruit"), outcome("complaints_sugar"), outcome("complaints_ice"), outcome("customers_bought"), outcome("customers_arrived"), revenue, spending,
      start.demo, last.demo, times.first_cup, times.first_sale, times.recipe_discovered, times.demo_completed, now];
    upsert(stands, row.map(cell));
    aggregate.cups += cups;
    for (const key of ["happy", "timeouts", "too_expensive", "wrong_order", "scams"]) aggregate[key] += outcome(key);
    aggregate.unhappy += outcome("customers_bought") - outcome("happy");
    aggregate.completed += last.demo === "completed" ? 1 : 0;
    aggregate.revenue += revenue;
    aggregate.spending += spending;
  });
  const matches = book.getSheetByName("Matches");
  upsert(matches, [p.match_id, status, p.mode, p.players, p.participants, p.minutes, p.steam_build, reports.length,
    aggregate.cups, aggregate.happy, aggregate.timeouts, aggregate.too_expensive, aggregate.wrong_order, aggregate.scams,
    aggregate.unhappy, aggregate.completed, aggregate.revenue, aggregate.spending, now, p.revision].map(cell));
}

function ingestLearning(book, p) {
  if (p.schema_version !== 2 || p.role !== "host" || !/^[a-zA-Z0-9_-]{8,80}$/.test(String(p.match_id || ""))) return reply({ok: false, error: "Invalid learning report"});
  const err = writeLearningRecords(book, p, new Date());
  if (err) return reply({ok: false, error: err});
  return reply({ok: true});
}

// Shared writer for learning events and records embedded in session
// payloads. Returns an error string, or "" on success.
function writeLearningRecords(book, p, now) {
  const records = Array.isArray(p.records) ? p.records : [{kind: p.kind, record: p.record}];
  if (!records.length || records.length > 10) return "Invalid record count";
  for (const detail of records) {
    const r = detail.record;
    if (!r || typeof r.id !== "string" || !r.id.length || r.id.length > 180 || !Number.isFinite(r.revision) || r.revision < 1) return "Invalid learning row";
    let sheet, row, revisionColumn;
    const id = p.match_id + ":" + r.id;
    if (detail.kind === "tutorial") {
      sheet = book.getSheetByName("Tutorial Steps");
      revisionColumn = 15;
      row = [id, p.match_id, r.stand_id, r.task_id, r.step_order, r.name, r.status, r.started_seconds, r.completed_seconds, r.elapsed_seconds, r.active_seconds, r.automatic, r.resumed, now, r.revision, p.steam_build];
    } else if (detail.kind === "batch") {
      sheet = book.getSheetByName("Pitcher Batches");
      revisionColumn = 40;
      const reasons = r.paid_reasons || {};
      const axes = r.paid_axes || {};
      const samples = r.sample_axes || {};
      row = [id, p.match_id, r.stand_id, r.id, r.batch_number, r.fruit_batch_number, r.fruit, r.fruit_count, r.water, r.sugar, r.ice, r.carried_in, r.recipe_known, r.started_seconds, r.day,
        r.cups_poured, r.paid_cups, r.paid_people, r.paid_happy, r.paid_unhappy, axes.sugar || 0, axes.ice || 0, axes.fruit || 0,
        reasons.too_sweet || 0, reasons.not_sweet_enough || 0, reasons.too_cold || 0, reasons.not_cold_enough || 0, reasons.too_strong || 0, reasons.not_enough_fruit || 0,
        r.sample_cups, r.sample_people, r.sample_happy, r.sample_unhappy, samples.sugar || 0, samples.ice || 0, samples.fruit || 0, r.temperature_min, r.temperature_max, now, r.revision, p.steam_build];
    } else {
      return "Invalid learning kind";
    }
    const existing = findRow(sheet, id);
    if (existing && number(sheet.getRange(existing, revisionColumn).getValue()) >= r.revision) continue;
    writeRow(sheet, existing || sheet.getLastRow() + 1, row.map(cell));
  }
  refreshLearningCharts(book);
  return "";
}

function median(values) {
  if (!values.length) return "";
  const sorted = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function refreshLearningCharts(book) {
  const data = book.getSheetByName("Chart Data v2");
  if (!data) return;
  if (data.getMaxColumns() < 56) data.insertColumnsAfter(data.getMaxColumns(), 56 - data.getMaxColumns());
  const steps = book.getSheetByName("Tutorial Steps");
  const groups = new Map();
  if (steps && steps.getLastRow() > 1) {
    steps.getRange(2, 1, steps.getLastRow() - 1, TUTORIAL_HEADERS.length).getValues().forEach(r => {
      if (String(r[1]).startsWith("TEST_")) return;
      if (!groups.has(r[3])) groups.set(r[3], {order: r[4], name: r[5], reached: new Set(), completed: new Set(), times: [], left: 0, active: 0});
      const g = groups.get(r[3]);
      g.reached.add(r[1] + ":" + r[2]);
      if (r[6] === "completed") {
        g.completed.add(r[1] + ":" + r[2]);
        if (!r[11] && !r[12] && typeof r[10] === "number") g.times.push(r[10]);
      }
      if (r[6] === "left_on_step") g.left++;
      if (r[6] === "active") g.active++;
    });
  }
  const summary = Array.from(groups.values()).sort((a, b) => a.order - b.order);
  data.getRange("Q1:X1").setValues([["Tutorial step", "Median active seconds", "Observed stands", "Completed stands", "Left on step", "Still observed active", "Step order", "Timing samples"]]);
  if (summary.length) data.getRange(2, 17, summary.length, 8).setValues(summary.map(g => [g.name, median(g.times), g.reached.size, g.completed.size, g.left, g.active, g.order, g.times.length]));
  const batches = book.getSheetByName("Pitcher Batches");
  const learning = new Map();
  if (batches && batches.getLastRow() > 1) {
    batches.getRange(2, 1, batches.getLastRow() - 1, BATCH_HEADERS.length).getValues().forEach(r => {
      if (String(r[1]).startsWith("TEST_") || r[6] !== "lemon" || r[11] || !(number(r[17]) || number(r[30]))) return;
      const index = number(r[5]);
      if (!learning.has(index)) learning.set(index, {people: 0, happy: 0, unhappy: 0, sugar: 0, ice: 0, fruit: 0, batches: 0, samples: 0, sampleUnhappy: 0, sampleSugar: 0, sampleIce: 0, sampleFruit: 0});
      const g = learning.get(index);
      g.people += number(r[17]); g.happy += number(r[18]); g.unhappy += number(r[19]);
      g.sugar += number(r[20]); g.ice += number(r[21]); g.fruit += number(r[22]); g.batches++;
      g.samples += number(r[30]); g.sampleUnhappy += number(r[32]);
      g.sampleSugar += number(r[33]); g.sampleIce += number(r[34]); g.sampleFruit += number(r[35]);
    });
  }
  data.getRange("Z1:AG1").setValues([["Lemon batch", "Unhappy %", "Sugar complaint %", "Ice complaint %", "Fruit complaint %", "Tasters", "Batches", "Happy %"]]);
  data.getRange("AI1:AJ1").setValues([["Tutorial bottleneck", "Median unpaused minutes"]]);
  const slow = summary.filter(g => g.times.length).sort((a, b) => median(b.times) - median(a.times)).slice(0, 8);
  data.getRange("AI2:AJ9").setValues(Array.from({length: 8}, (_, i) => slow[i] ? [slow[i].name, median(slow[i].times) / 60] : ["", ""]));
  data.getRange("BC1:BD1").setValues([["Step left unfinished", "Known exits"]]);
  const exits = summary.filter(g => g.left > 0).sort((a, b) => b.left - a.left).slice(0, 8);
  data.getRange("BC2:BD9").setValues(Array.from({length: 8}, (_, i) => exits[i] ? [exits[i].name, exits[i].left] : ["", ""]));
  const rows = Array.from(learning.entries()).sort((a, b) => a[0] - b[0]);
  const percent = (count, total) => total ? 100 * count / total : "";
  if (rows.length) data.getRange(2, 26, rows.length, 8).setValues(rows.map(([index, g]) => [index, percent(g.unhappy, g.people), percent(g.sugar, g.people), percent(g.ice, g.people), percent(g.fruit, g.people), g.people, g.batches, percent(g.happy, g.people)]));
  data.getRange("AL1:AP1").setValues([["Lemon batch", "Unhappy %", "Sugar complaint %", "Ice complaint %", "Fruit complaint %"]]);
  if (rows.length) data.getRange(2, 38, rows.length, 5).setValues(rows.map(([index, g]) => [index, percent(g.sampleUnhappy, g.samples), percent(g.sampleSugar, g.samples), percent(g.sampleIce, g.samples), percent(g.sampleFruit, g.samples)]));
}

function getBook() {
  return SpreadsheetApp.openById(PropertiesService.getScriptProperties().getProperty("SHEET_ID"));
}

function ensureTab(book, name, headers) {
  const sheet = book.getSheetByName(name) || book.insertSheet(name);
  if (sheet.getMaxColumns() < headers.length) sheet.insertColumnsAfter(sheet.getMaxColumns(), headers.length - sheet.getMaxColumns());
  sheet.getRange(1, 1, 1, headers.length).setValues([headers]).setFontWeight("bold").setBackground("#dce6f1").setWrap(true);
  sheet.setFrozenRows(1);
  sheet.setFrozenColumns(1);
  sheet.setColumnWidths(1, headers.length, 145);
  sheet.getRange(2, 1, Math.max(1, sheet.getMaxRows() - 1), headers.length).setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
  return sheet;
}

function findRow(sheet, id) {
  if (sheet.getLastRow() < 2) return 0;
  const found = sheet.getRange(2, 1, sheet.getLastRow() - 1, 1).createTextFinder(String(id)).matchEntireCell(true).useRegularExpression(false).findNext();
  return found ? found.getRow() : 0;
}

function upsert(sheet, row) {
  writeRow(sheet, findRow(sheet, row[0]) || sheet.getLastRow() + 1, row);
}

function writeRow(sheet, index, row) {
  if (index > sheet.getMaxRows()) sheet.insertRowsAfter(sheet.getMaxRows(), 500);
  sheet.getRange(index, 1, 1, row.length).setValues([row]);
  row.forEach((value, column) => {
    if (Object.prototype.toString.call(value) === "[object Date]") sheet.getRange(index, column + 1).setNumberFormat("dd mmm yyyy HH:mm:ss");
  });
}

function readRows(p) {
  const tab = p.tab || "Sessions";
  if (!["Sessions", "Matches", "Stands", "Tutorial Steps", "Pitcher Batches"].includes(tab)) return reply({ok: false, error: "Invalid tab"});
  const sheet = getBook().getSheetByName(tab);
  const offset = Math.max(0, Math.floor(number(p.offset)));
  const limit = Math.min(200, Math.max(1, Math.floor(number(p.limit) || 100)));
  const total = Math.max(0, sheet.getLastRow() - 1);
  const count = Math.min(limit, Math.max(0, total - offset));
  const columns = sheet.getLastColumn();
  return reply({ok: true, headers: sheet.getRange(1, 1, 1, columns).getValues()[0], rows: count ? sheet.getRange(offset + 2, 1, count, columns).getValues() : [], total, offset});
}

function cell(value) {
  if (value == null) return "";
  if (Array.isArray(value)) return cell(value.join(", "));
  if (typeof value !== "string") return value;
  const text = value.slice(0, 47000);
  return /^[=+\-@\t\r\n]/.test(text) ? "'" + text : text;
}

function number(value) {
  const result = Number(value);
  return Number.isFinite(result) ? result : 0;
}

function timestamp(value) {
  if (Object.prototype.toString.call(value) === "[object Date]") return Number.isFinite(value.getTime()) ? value : "";
  if (typeof value !== "string" || !/^\d{4}-\d\d-\d\dT/.test(value)) return "";
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : "";
}

function localDateColumns(sheet, columns) {
  columns.forEach(column => {
    const count = sheet.getLastRow() - 1;
    if (count > 0) {
      const range = sheet.getRange(2, column, count, 1);
      range.setValues(range.getValues().map(([value]) => [timestamp(value)]));
    }
    sheet.getRange(2, column, sheet.getMaxRows() - 1, 1).setNumberFormat("dd mmm yyyy HH:mm:ss");
  });
}

function difference(end, start) {
  return end != null && start != null ? number(end) - number(start) : "";
}

function reply(value) {
  return ContentService.createTextOutput(JSON.stringify(value)).setMimeType(ContentService.MimeType.JSON);
}

function buildPreview(book) {
  let sheet = book.getSheetByName("Preview");
  if (sheet) return;
  sheet = book.insertSheet("Preview");
  sheet.setHiddenGridlines(true);
  sheet.setColumnWidths(1, 8, 115);
  sheet.getRange("A1:H2").merge().setValue("PREVIEW — FICTIONAL EXAMPLE, NOT REAL REPORTS").setBackground("#17324d").setFontColor("white").setFontSize(16).setFontWeight("bold");
  sheet.getRange("A4:H5").merge().setValue("ONE co-op match • TWO participants • ONE shared stand • 24 cups counted ONCE\nA versus match would have separate stand totals. Each player's FPS and clicks remain separate.").setWrap(true).setBackground("#dce6f1");
  sheet.getRange("A7:H10").setValues([
    ["Participant", "Role", "Mode", "Peak group", "Minutes", "Gameplay FPS", "Wishlist clicks", "Stand"],
    ["Player A", "host", "coop", 2, 18, 120, 1, "Shared stand"],
    ["Player B", "client", "coop", 2, 17, 95, 0, "Shared stand"],
    ["Match total", "", "coop", 2, 18, "Not added together", 1, "24 cups total"]
  ]).setWrap(true);
  sheet.getRange("A7:H7").setBackground("#dce6f1").setFontWeight("bold");
  sheet.getRange("A12:H13").merge().setValue("Real data: Overview = match summaries; Matches = one row per match; Stands = customer outcomes and milestones; Sessions = each person's stats.\nLegacy reports remain available, but cannot reliably be combined into historical matches.").setWrap(true);
  const data = book.getSheetByName("Chart Data v2");
  data.getRange("O1:P6").setValues([["Example outcomes", "Customers"], ["Happy buyers", 12], ["Unhappy buyers", 3], ["Timeouts", 2], ["Price rejections", 1], ["Wrong orders", 0]]);
  sheet.insertChart(sheet.newChart().setChartType(Charts.ChartType.BAR).addRange(data.getRange("O1:P6")).setNumHeaders(1).setOption("title", "FICTIONAL EXAMPLE — customer outcomes").setOption("width", 850).setOption("height", 320).setPosition(16, 1, 0, 0).build());
}

function layoutOverview() {
  const sheet = getBook().getSheetByName("Overview");
  if (!sheet) return;
  sheet.setColumnWidths(1, 18, 85);
  sheet.setRowHeights(1, 65, 20);
  sheet.setRowHeight(4, 34);
  sheet.setRowHeight(8, 34);
  sheet.setFrozenRows(2);
  const positions = [[16, 1], [16, 7], [16, 13], [32, 1], [32, 7], [32, 13], [48, 1], [48, 7]];
  sheet.getCharts().forEach((chart, index) => {
    if (index >= positions.length) return;
    const [row, column] = positions[index];
    sheet.updateChart(chart.modify()
      .setPosition(row, column, 0, 0)
      .setOption("width", 490)
      .setOption("height", 290)
      .setOption("fontSize", 12)
      .setOption("titleTextStyle", {fontSize: 14})
      .build());
  });
}

function buildOverview(book) {
  let sheet = book.getSheetByName("Overview");
  if (!sheet) sheet = book.insertSheet("Overview");
  sheet.setHiddenGridlines(true);
  sheet.setColumnWidths(1, 8, 110);
  sheet.getRange("A1:H2").merge().setValue("DEMO ANALYTICS — MATCHES & PLAYERS").setBackground("#17324d").setFontColor("white").setFontWeight("bold").setFontSize(18);
  const cards = [
    ["A4:B4", "A5:B6", "New matches", '=COUNTIFS(Matches!A2:A,"<>",Matches!A2:A,"<>TEST_*")'],
    ["D4:E4", "D5:E6", "New participant reports", '=COUNTIFS(Sessions!AL2:AL,"v2",Sessions!A2:A,"<>TEST_*")'],
    ["G4:H4", "G5:H6", "Completed stands", '=SUMIF(Matches!A2:A,"<>TEST_*",Matches!P2:P)'],
    ["A8:B8", "A9:B10", "Wishlist button clicks (new)", '=SUMIFS(Sessions!Y2:Y,Sessions!AL2:AL,"v2",Sessions!A2:A,"<>TEST_*")+SUMIFS(Sessions!Z2:Z,Sessions!AL2:AL,"v2",Sessions!A2:A,"<>TEST_*")'],
    ["D8:E8", "D9:E10", "Legacy reports (not matches)", '=COUNTIFS(Sessions!AL2:AL,"legacy",Sessions!A2:A,"<>TEST_*")'],
    ["G8:H8", "G9:H10", "New ended participant reports", '=COUNTIFS(Sessions!AL2:AL,"v2",Sessions!B2:B,"Ended",Sessions!A2:A,"<>TEST_*")'],
    ["J4:L4", "J5:L6", "Average ended match (min)", '=IFERROR(ROUND(AVERAGEIFS(Matches!F2:F,Matches!B2:B,"Ended",Matches!A2:A,"<>TEST_*"),1),0)'],
    ["N4:P4", "N5:P6", "Median ended match (min)", '=IFERROR(ROUND(MEDIAN(FILTER(Matches!F2:F,Matches!B2:B="Ended",LEFT(Matches!A2:A,5)<>"TEST_")),1),0)'],
    ["J8:L8", "J9:L10", "Recorded match-hours (incl. open)", '=ROUND(SUMIF(Matches!A2:A,"<>TEST_*",Matches!F2:F)/60,1)'],
    ["N8:P8", "N9:P10", "Longest ended match (min)", '=IFERROR(ROUND(MAX(FILTER(Matches!F2:F,Matches!B2:B="Ended",LEFT(Matches!A2:A,5)<>"TEST_")),1),0)']
  ];
  cards.forEach(([label, value, title, formula]) => {
    sheet.getRange(label).merge().setValue(title).setBackground("#dce6f1").setWrap(true).setFontWeight("bold");
    sheet.getRange(value).merge().setFormula(formula).setBackground("#eef4fa").setFontSize(25).setHorizontalAlignment("center");
  });
  sheet.getRange("A12:H14").merge().setValue("Matches = one host's authoritative record. Participants = each player's performance/clicks.\nPeak connected and participant connections are NOT unique humans. Legacy data is excluded from new match charts.\nNo end received can mean still playing, disconnected, or failed submission—not proof of a crash.").setWrap(true).setFontColor("#526171");
  const data = book.getSheetByName("Chart Data v2") || book.insertSheet("Chart Data v2");
  data.getRange("A1:B3").setValues([["Mode", "Matches"], ["coop", ""], ["versus", ""]]);
  data.getRange("B2").setFormula('=COUNTIFS(Matches!C2:C,A2,Matches!A2:A,"<>TEST_*")');
  data.getRange("B3").setFormula('=COUNTIFS(Matches!C2:C,A3,Matches!A2:A,"<>TEST_*")');
  data.getRange("D1:E5").setValues([["Peak group size", "Matches"], [1, ""], [2, ""], [3, ""], [4, ""]]);
  for (let i = 2; i <= 5; i++) data.getRange(i, 5).setFormula('=COUNTIFS(Matches!D2:D,D' + i + ',Matches!A2:A,"<>TEST_*")');
  data.getRange("G1:H7").setValues([["Customer outcomes", "Count"], ["Happy buyers", ""], ["Unhappy buyers", ""], ["Timeouts", ""], ["Price rejections", ""], ["Wrong orders", ""], ["Scams", ""]]);
  ["J", "O", "K", "L", "M", "N"].forEach((col, i) => data.getRange(i + 2, 8).setFormula('=SUMIF(Matches!A2:A,"<>TEST_*",Matches!' + col + '2:' + col + ')'));
  data.getRange("J1:K6").setValues([["Milestone during match", "Stands"], ["First cup", ""], ["First sale", ""], ["Recipe discovery", ""], ["Demo completion", ""], ["Completed before match", ""]]);
  ["Y", "Z", "AA", "AB"].forEach((col, i) => data.getRange(i + 2, 11).setFormula('=COUNTIFS(Stands!' + col + '2:' + col + ',">=0",Stands!' + col + '2:' + col + ',"<>",Stands!B2:B,"<>TEST_*")'));
  data.getRange("K6").setFormula('=COUNTIFS(Stands!W2:W,"completed",Stands!B2:B,"<>TEST_*")');
  data.getRange("M1").setFormula('=IFERROR(QUERY({Sessions!AD2:AD,Sessions!AB2:AB,Sessions!AL2:AL,Sessions!B2:B,Sessions!A2:A},"select Col1, avg(Col2) where Col3 = \'v2\' and Col4 = \'Ended\' and Col2 > 0 and not Col5 starts with \'TEST_\' group by Col1 label Col1 \'GPU\', avg(Col2) \'Average FPS\'",0),"")');
  if (data.getMaxColumns() < 56) data.insertColumnsAfter(data.getMaxColumns(), 56 - data.getMaxColumns());
  data.getRange("AI1:AJ1").setValues([["Tutorial bottleneck", "Median unpaused minutes"]]);
  data.getRange("Z1:AD1").setValues([["Lemon batch", "Unhappy %", "Sugar complaint %", "Ice complaint %", "Fruit complaint %"]]);
  sheet.getRange("J1:L2").merge().setValue("Recipe learning source (lemon)").setWrap(true).setFontWeight("bold");
  const selector = sheet.getRange("M1:O2").merge();
  const selected = selector.getValue();
  selector.setValue(["Customers", "Free samples"].includes(selected) ? selected : "Customers").setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(["Customers", "Free samples"], true).setAllowInvalid(false).build()).setBackground("#fff2cc");
  data.getRange("AL1:AP1").setValues([["Lemon batch", "Unhappy %", "Sugar complaint %", "Ice complaint %", "Fruit complaint %"]]);
  data.getRange("AW1").setFormula('=ARRAYFORMULA(IF(Overview!M1="Free samples",AL1:AP21,Z1:AD21))');
  data.getRange("AT1:AU6").setValues([["Ended match length", "Matches"], ["Under 5 min", ""], ["5–15 min", ""], ["15–30 min", ""], ["30–60 min", ""], ["60+ min", ""]]);
  [[0,5],[5,15],[15,30],[30,60],[60,null]].forEach(([low, high], i) => {
    let formula = '=COUNTIFS(Matches!B2:B,"Ended",Matches!A2:A,"<>TEST_*",Matches!F2:F,">=' + low + '"';
    if (high != null) formula += ',Matches!F2:F,"<' + high + '"';
    data.getRange(i + 2, 47).setFormula(formula + ')');
  });
  sheet.getRange("J12:R14").merge().setValue("Tutorial: unpaused stand time; auto-satisfied and resumed partial steps excluded from timing medians.\nBatch learning: choose customers or free samples above; carried-in/unattributed batches excluded.\nPlaytime cards use matches, not the sum of every co-op player's duplicate duration.").setWrap(true).setFontColor("#526171");
  const charts = [
    ["A1:B3", Charts.ChartType.PIE, "New matches — selected mode"],
    ["D1:E5", Charts.ChartType.COLUMN, "New matches — peak players"],
    ["G1:H7", Charts.ChartType.BAR, "Customer outcomes — once per stand"],
    ["AI1:AJ9", Charts.ChartType.BAR, "Tutorial: 8 slowest completed steps (min)"],
    ["AW1:BA21", Charts.ChartType.LINE, "Lemon learning: selected source, batches 1–20"],
    ["AT1:AU6", Charts.ChartType.COLUMN, "How long matches lasted"],
    ["M1:N200", Charts.ChartType.BAR, "Gameplay FPS by GPU"],
    ["BC1:BD9", Charts.ChartType.BAR, "Tutorial: steps unfinished at known exit"]
  ];
  const existing = sheet.getCharts();
  charts.forEach(([range, type, title], index) => {
    const builder = existing[index] ? existing[index].modify().clearRanges() : sheet.newChart();
    builder.setChartType(type).addRange(data.getRange(range)).setNumHeaders(1).setOption("title", title).setOption("width", 490).setOption("height", 290).setPosition(16 + 16 * Math.floor(index / 3), 1 + 6 * (index % 3), 0, 0);
    if (index === 4) builder.setOption("vAxis", {minValue: 0, maxValue: 100});
    if (existing[index]) sheet.updateChart(builder.build()); else sheet.insertChart(builder.build());
  });
  sheet.getRange("M48:R48").merge().setValue("LATEST MATCHES — last reported playtime").setBackground("#dce6f1").setFontWeight("bold");
  sheet.getRange("M49").setFormula('=IFERROR(QUERY(Matches!A1:T,"select C,D,F,B,S,A where A is not null and not A starts with \'TEST_\' order by S desc limit 10 label C \'Mode\', D \'Players\', F \'Minutes\', B \'Status\', S \'Last update\', A \'Match ID\'",1),"")');
  sheet.getRange("M49:R60").setFontSize(10).setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
  sheet.getRange("O50:O60").setNumberFormat("0.0");
  sheet.getRange("Q50:Q60").setNumberFormat("dd/MM HH:mm");
  book.setActiveSheet(sheet);
}

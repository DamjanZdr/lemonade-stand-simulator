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
    if (!["session_start", "checkpoint", "session_end"].includes(p.event)) return reply({ok: false, error: "Invalid event"});
    const lock = LockService.getScriptLock();
    lock.waitLock(10000);
    try {
      const book = getBook();
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
      if (p.schema_version === 2 && p.role === "host" && /^[a-zA-Z0-9_-]{8,80}$/.test(String(p.match_id || ""))) updateMatch(book, p, now);
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
  if (!["Sessions", "Matches", "Stands"].includes(tab)) return reply({ok: false, error: "Invalid tab"});
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

function buildOverview(book) {
  let sheet = book.getSheetByName("Overview");
  const fresh = !sheet;
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
    ["G8:H8", "G9:H10", "New ended participant reports", '=COUNTIFS(Sessions!AL2:AL,"v2",Sessions!B2:B,"Ended",Sessions!A2:A,"<>TEST_*")']
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
  if (fresh) {
    const charts = [["A1:B3", Charts.ChartType.PIE, "New matches — selected mode", 16], ["D1:E5", Charts.ChartType.COLUMN, "New matches — peak players", 34], ["G1:H7", Charts.ChartType.BAR, "Customer outcomes — counted once per stand", 52], ["J1:K6", Charts.ChartType.BAR, "Progress milestones — during this match", 70], ["M1:N200", Charts.ChartType.BAR, "Gameplay FPS by GPU — new ended reports", 88]];
    charts.forEach(([range, type, title, row]) => sheet.insertChart(sheet.newChart().setChartType(type).addRange(data.getRange(range)).setNumHeaders(1).setOption("title", title).setOption("width", 850).setOption("height", 300).setPosition(row, 1, 0, 0).build()));
  }
  book.setActiveSheet(sheet);
}

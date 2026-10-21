const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const context = vm.createContext({console});
vm.runInContext(fs.readFileSync(path.join(__dirname, 'sheets_analytics.gs'), 'utf8'), context);
vm.runInContext(`
var testTables = {Sessions: [], Matches: [], Stands: [], "Tutorial Steps": [], "Pitcher Batches": []};
var testHeaders = {};
function columnIndex(text) {return [...text].reduce((n, c) => n * 26 + c.charCodeAt(0) - 64, 0);}
function rangeArgs(row, col, count, width) {
 if (typeof row === 'string') {
   const m = row.match(/^([A-Z]+)([0-9]+)(?::([A-Z]+)([0-9]+))?$/);
   return [+m[2], columnIndex(m[1]), m[4] ? +m[4] - +m[2] + 1 : 1, m[3] ? columnIndex(m[3]) - columnIndex(m[1]) + 1 : 1];
 }
 return [row, col, count || 1, width || 1];
}
var testBook = {getSheetByName: name => !testTables[name] ? null : ({name,
 getLastRow: () => testTables[name].length + 1,
 getMaxRows: () => 1000,
 getMaxColumns: () => 60,
 getRange: (...args) => {
   const [row, col, count, width] = rangeArgs(...args);
   const range = {
     getValues: () => Array.from({length:count}, (_, i) => Array.from({length:width}, (_, j) => ((row+i === 1 ? testHeaders[name] : testTables[name][row+i-2]) || [])[col+j-1] ?? '')),
     getValue: () => range.getValues()[0][0],
     setValues: values => {values.forEach((r, i) => {
       const target = row+i === 1 ? (testHeaders[name] ||= []) : (testTables[name][row+i-2] ||= []);
       r.forEach((value, j) => target[col+j-1] = value);
     }); return range;},
     setNumberFormat: () => range
   };
   return range;
 }
})};
getBook = () => testBook;
findRow = (sheet, id) => {const i = testTables[sheet.name].findIndex(r => r && r[0] === id); return i < 0 ? 0 : i + 2;};
reply = p => p;
var PropertiesService = {getScriptProperties: () => ({getProperty: () => 'private'})};
var LockService = {getScriptLock: () => ({waitLock: () => {}, releaseLock: () => {}})};
function submit(p) {return doPost({postData: {contents: JSON.stringify(p)}});}
`, context);
const call = p => context.submit(p);
const snap = (cups, happy, timeouts) => ({day:1,money:200,cups,revenue:cups*2,spending:10,demo:'in progress',outcomes:{happy,timeouts,customers_bought:happy}});
const base = {schema_version:2,session_id:'TEST_participant01',match_id:'TEST_shared_match01',mode:'coop',role:'host',players:2,participants:2,revision:1,event:'session_start',start:snap(5,2,1),latest:snap(5,2,1),stand_reports:[{stand_id:'StandUnit',start:snap(5,2,1),latest:snap(5,2,1),milestones:{}}]};
assert.equal(call(base).ok,true);
const checkpoint = {...base,revision:2,event:'checkpoint',minutes:5,latest:snap(15,7,3),stand_reports:[{stand_id:'StandUnit',start:snap(5,2,1),latest:snap(15,7,3),milestones:{first_sale:10}}]};
assert.equal(call(checkpoint).ok,true);
assert.equal(context.testTables.Sessions[0][3],'');
assert.equal(context.testTables.Matches[0][8],10);
assert.equal(context.testTables.Matches[0][9],5);
assert.equal(context.testTables.Matches[0][10],2);
assert.equal(context.testTables.Matches[0][14],0);
assert.equal(call({...checkpoint,role:'client',session_id:'TEST_participant02'}).ok,true);
assert.equal(context.testTables.Matches.length,1);
assert.equal(context.testTables.Matches[0][8],10);
assert.equal(call({...checkpoint,revision:3,event:'session_end',end:snap(15,7,3),reason:'quit'}).ok,true);
assert.equal(context.testTables.Sessions[0][1],'Ended');
assert.equal(call(checkpoint).ignored,'Ended already');
assert.equal(call({...checkpoint,revision:1,event:'session_end'}).ignored,'Stale revision');
assert.equal(context.cell('=IMPORTXML("bad")').startsWith("'"),true);
assert.equal(call({action:'read',read_key:'wrong'}).error,'Unauthorized');
const legacy = context.sessionRow({session_id:'legacy01',event:'session_end',start:{cups:0},end:{cups:5}},[], '');
assert.equal(legacy[37],'legacy');
assert.equal(legacy[17],5);
assert.equal(context.timestamp('2026-10-20T18:00:00Z').toISOString(),'2026-10-20T18:00:00.000Z');

context.testTables['Chart Data v2'] = [];
const learning = {schema_version:2,event:'learning',session_id:'participant_new1',match_id:'learning_match01',role:'host',steam_build:123};
const task = {id:'StandUnit:demo_fill_cup:1',stand_id:'StandUnit',task_id:'demo_fill_cup',step_order:17,name:'Fill a cup',status:'active',started_seconds:10,completed_seconds:null,elapsed_seconds:20,active_seconds:10,automatic:false,resumed:false,revision:1};
assert.equal(call({...learning,records:[{kind:'tutorial',record:task}]}).ok,true);
assert.equal(context.testTables['Tutorial Steps'].length,1);
assert.equal(call({...learning,records:[{kind:'tutorial',record:{...task,status:'completed',completed_seconds:50,elapsed_seconds:40,active_seconds:30,revision:3}}]}).ok,true);
assert.equal(call({...learning,records:[{kind:'tutorial',record:task}]}).ok,true);
assert.equal(context.testTables['Tutorial Steps'][0][6],'completed');
assert.equal(context.testTables['Chart Data v2'][0][17],30);
assert.equal(context.testTables['Chart Data v2'][0][35],0.5);
const auto = {...task,id:'StandUnit:demo_place_equipment:1',task_id:'demo_place_equipment',step_order:5,name:'Place equipment',status:'completed',automatic:true,revision:4};
const resumed = {...task,id:'StandUnit:demo_fill_water:1',task_id:'demo_fill_water',step_order:14,name:'Fill water',status:'completed',resumed:true,revision:5};
assert.equal(call({...learning,records:[{kind:'tutorial',record:auto},{kind:'tutorial',record:resumed}]}).ok,true);
assert.equal(context.testTables['Chart Data v2'][0][17],'');
assert.equal(context.testTables['Chart Data v2'][2][17],30);
const batch = {id:'batch_first',stand_id:'StandUnit',batch_number:1,fruit_batch_number:1,fruit:'lemon',carried_in:false,recipe_known:false,paid_cups:5,paid_people:4,paid_happy:1,paid_unhappy:3,paid_reasons:{too_sweet:2},paid_axes:{sugar:2,ice:1,fruit:0},sample_people:2,sample_unhappy:2,sample_axes:{sugar:2},revision:6};
assert.equal(call({...learning,records:[{kind:'batch',record:batch}]}).ok,true);
assert.equal(context.testTables['Pitcher Batches'].length,1);
assert.equal(context.testTables['Chart Data v2'][0][26],75);
assert.equal(context.testTables['Chart Data v2'][0][27],50);
assert.equal(context.testTables['Chart Data v2'][0][30],4);
assert.equal(call({...learning,records:[{kind:'batch',record:{...batch,id:'batch_carried',carried_in:true,paid_people:100,revision:7}}]}).ok,true);
assert.equal(context.testTables['Chart Data v2'][0][30],4);
assert.equal(context.testTables['Chart Data v2'][0][38],100);
assert.equal(call({...learning,records:[{kind:'batch',record:{...batch,id:'batch_other_stand',stand_id:'StandUnit2',paid_people:6,paid_happy:4,paid_unhappy:2,revision:8}}]}).ok,true);
assert.equal(context.testTables['Chart Data v2'][0][26],50);
assert.equal(context.testTables['Chart Data v2'][0][30],10);
assert.equal(call({...learning,records:[{kind:'batch',record:{...batch,id:'sample_only',fruit_batch_number:2,paid_people:0,paid_cups:0,paid_happy:0,paid_unhappy:0,paid_axes:{},sample_people:4,sample_unhappy:1,sample_axes:{ice:1},revision:9}}]}).ok,true);
assert.equal(context.testTables['Chart Data v2'][1][26],'');
assert.equal(context.testTables['Chart Data v2'][1][38],25);
assert.equal(call({...learning,role:'client',records:[{kind:'batch',record:batch}]}).ok,false);
assert.equal(call({...learning,records:Array(11).fill({kind:'batch',record:batch})}).ok,false);
const left = {...task,id:'StandUnit:demo_master_lemon:1',task_id:'demo_master_lemon',name:'Find the recipe',status:'left_on_step',step_order:23,revision:10};
assert.equal(call({...learning,records:[{kind:'tutorial',record:left}]}).ok,true);
assert.equal(context.testTables['Chart Data v2'][0][54],'Find the recipe');
assert.equal(context.testTables['Chart Data v2'][0][55],1);
// Embedded records inside session payloads ingest like learning events and
// acknowledge records_accepted so the sender can drop its queued copies.
const embeddedTask = {...task,id:'StandUnit:demo_order_supplies:1',task_id:'demo_order_supplies',step_order:2,name:'Order supplies',status:'completed',completed_seconds:30,elapsed_seconds:25,active_seconds:20,revision:11};
const embeddedEnd = call({...checkpoint,revision:4,event:'session_end',end:snap(15,7,3),records:[{kind:'tutorial',record:embeddedTask}]});
assert.equal(embeddedEnd.ok,true);
assert.equal(embeddedEnd.records_accepted,true);
assert.equal(context.testTables['Tutorial Steps'].some(r => r && r[0] === 'TEST_shared_match01:StandUnit:demo_order_supplies:1'),true);
assert.equal(call({...checkpoint,role:'client',session_id:'TEST_participant03',revision:1,records:[{kind:'tutorial',record:embeddedTask}]}).records_accepted,undefined);
assert.equal(call({...checkpoint,session_id:'TEST_fresh01',revision:1,event:'checkpoint'}).records_accepted,undefined);
assert.equal(context.testTables.Sessions.length,4);
console.log('PASS: host-only match totals; checkpoints; stale revisions; private reads; legacy/date mapping; tutorial upserts and medians; auto/resumed exclusions; weighted batch trends; sample/carried-in separation; bounded learning pages; embedded session records');

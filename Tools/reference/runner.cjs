"use strict";
const fs = require("node:fs"), path = require("node:path"), vm = require("node:vm");
const {createHash} = require("node:crypto"), {spawnSync} = require("node:child_process");
const {Document} = require("./dom.cjs"), Harness = require("./host.js");
const ROOT = path.resolve(__dirname,"../.."), CACHE = path.join(ROOT,".tmp-paperclips");
const ORDER = ["combat.js","globals.js","projects.js","main.js"];
const sha256 = bytes => createHash("sha256").update(bytes).digest("hex");

function inputs(cache = CACHE) {
    const lock = JSON.parse(fs.readFileSync(path.join(ROOT,"docs/reference/paperclips.lock.json"),"utf8"));
    if (JSON.stringify(lock.script_order) !== JSON.stringify(ORDER)) throw new Error("Unexpected source order");
    const spec = fs.readFileSync(path.join(ROOT,"docs/plan/Time-Is-Money-Implementation-Spec.md"),"utf8");
    const files = {};
    for (const file of lock.files) {
        if (!["index2.html",...ORDER].includes(file.name) || !spec.includes(file.sha256))
            throw new Error("Lock does not match owner specification");
        const bytes = fs.readFileSync(path.join(cache,file.name));
        if (sha256(bytes) !== file.sha256 || bytes.length !== file.bytes) throw new Error("Reference mismatch: "+file.name);
        files[file.name] = bytes.toString("utf8");
    }
    if (Object.keys(files).length !== 5) throw new Error("Expected all five pinned files");
    const index = JSON.parse(fs.readFileSync(path.join(ROOT,"docs/reference/inventory.json"),"utf8"));
    for (const file of lock.files)
        if (index.source_sha256[file.name] !== file.sha256) throw new Error("Inventory/source pin mismatch");
    return {lock,files,index,cache};
}
function config(source, random, cosmetic) {
    const stateNames = [...new Set(ORDER.flatMap(name => [
        ...source.index.sources[name].top_level_declarations,
        ...source.index.sources[name].implicit_global_write_candidates
    ].map(entry=>entry.name)))].sort();
    return {stateNames,domIds:source.index.html_ids,random,cosmetic,maxCallbacks:2000,
            calls:["blink","hypnoDroneEvent","createBattle","save","load","refresh"]};
}
function load(trace, source = inputs()) {
    const parsed = spawnSync(process.env.TIM_PYTHON || "python", [
        path.join(__dirname,"parse_html.py"),path.join(source.cache,"index2.html")
    ], {encoding:"utf8",maxBuffer:2*1024*1024});
    if (parsed.status !== 0) throw new Error("HTML parser failed: "+parsed.stderr);
    const context = vm.createContext({console});
    const global = vm.runInContext("globalThis",context);
    global.window = global;
    global.document = new Document(JSON.parse(parsed.stdout),
        body=>vm.runInContext("(function(event){"+body+"})",context,{timeout:1000}));
    global.document.drawing = trace.drawing !== false;
    for (const id of source.index.html_ids) {
        if (!(id in global)) global[id] = global.document.getElementById(id);
    }
    global.location = {reload(){throw new Error("Reload requires an explicit future host decision");}};
    const harness = Harness.create(global,config(source,trace.random,trace.cosmetic));
    for (const name of ORDER) vm.runInContext(source.files[name],context,{filename:name,timeout:5000});
    return {global,harness,source,context};
}
// prepare(runner) may alter a loaded runner before the trace starts; tests use it
// to inject deliberate divergences.
function run(trace, source = inputs(), prepare = null) {
    const runner = load(trace,source);
    if (prepare) prepare(runner);
    const result=runner.harness.run(trace);
    result.input={fixture:trace.fixture || {},commands:trace.commands || [],until:trace.until,
        random_sha256:sha256(JSON.stringify(trace.random)),trace_sha256:sha256(JSON.stringify(trace))};
    return {...runner,trace,result};
}
// Inventory scope for each observed file:line:column draw label.
// The inventory records random calls by line; a label adds the column.
const scopeCache=new WeakMap();
function siteScope(site, source) {
    if (!scopeCache.has(source.index)) {
        const known={};
        for (const file of ORDER) for (const call of source.index.sources[file].random_calls)
            known[file+":"+call.line]=call.scope;
        scopeCache.set(source.index,known);
    }
    const [file,line]=site.split(":");
    return scopeCache.get(source.index)[file+":"+line] || null;
}
function drawSites(events, source) {
    const counts={};
    for (const event of events) if (event.action==="draw") {
        counts[event.site] ??= {scope:siteScope(event.site,source),draws:0};
        counts[event.site].draws++;
    }
    return counts;
}
// Trace document consumed by the first-divergence comparator. Full mode keeps
// checkpoint JSON so state differences resolve to a field instead of a hash.
function report(result, source, full = false) {
    return {schema:Harness.TRACE_SCHEMA.version,source_sha256:source.index.source_sha256,input:result.input,
            checkpoints:result.checkpoints.map(({json,...meta})=>({...meta,sha256:sha256(json),...(full ? {json} : {})})),
            events:result.events,draws:result.draws,draw_sites:drawSites(result.events,source),
            events_sha256:sha256(JSON.stringify(result.events)),
            final_sha256:sha256(JSON.stringify(Harness.encode(result.final)))};
}
// Adds inventory scopes to the differing draw labels.
function compare(left, right, source = null) {
    const found=Harness.compareTraces(left,right);
    if (found && source) for (const side of ["left","right"])
        if (found[side]?.action==="draw") found[side]={...found[side],scope:siteScope(found[side].site,source)};
    return found;
}
// Restrict a full reference document to a port's declared projection: the named
// state globals, control disabled flags, message readouts, timers and draw count.
// Events are kept whole, so every timer and labeled draw is still compared.
function project(doc, projection) {
    return {...doc,checkpoints:doc.checkpoints.map(({json,sha256,...meta})=>{
        if (json===undefined) throw new Error("Projection needs full checkpoint JSON");
        const point=JSON.parse(json), state={}, dom={};
        for (const key of projection.state) if (Object.hasOwn(point.state,key)) state[key]=point.state[key];
        for (const id of projection.disabled) dom[id]={disabled:point.dom[id].disabled};
        for (const id of projection.html) dom[id]={html:point.dom[id].html};
        return {...meta,json:JSON.stringify({state,dom,timers:point.timers,draws:point.draws})};
    })};
}
const firstDifference=Harness.firstDifference;
module.exports = {ROOT,CACHE,ORDER,sha256,inputs,config,load,run,report,compare,project,siteScope,firstDifference};

if (require.main === module) {
    try {
        const args=process.argv.slice(2), full=args[0]==="--full";
        if (args.length !== (full ? 2 : 1)) throw new Error("Usage: node Tools/reference/runner.cjs [--full] <trace.json>");
        const trace=JSON.parse(fs.readFileSync(args.at(-1),"utf8"));
        const {result,source}=run(trace);
        console.log(JSON.stringify(report(result,source,full),null,full ? 0 : 2));
    } catch (error) { console.error(error.stack); process.exitCode=1; }
}

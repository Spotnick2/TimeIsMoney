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
function config(source, random) {
    const stateNames = [...new Set(ORDER.flatMap(name => [
        ...source.index.sources[name].top_level_declarations,
        ...source.index.sources[name].implicit_global_write_candidates
    ].map(entry=>entry.name)))].sort();
    return {stateNames,domIds:source.index.html_ids,random,maxCallbacks:2000,
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
    const harness = Harness.create(global,config(source,trace.random));
    for (const name of ORDER) vm.runInContext(source.files[name],context,{filename:name,timeout:5000});
    return {global,harness,source};
}
function run(trace, source = inputs()) {
    const runner = load(trace,source);
    const result=runner.harness.run(trace);
    result.input={fixture:trace.fixture || {},commands:trace.commands || [],until:trace.until,
        random_sha256:sha256(JSON.stringify(trace.random)),trace_sha256:sha256(JSON.stringify(trace))};
    return {...runner,trace,result};
}
function report(result, source) {
    return {schema:1,source_sha256:source.index.source_sha256,input:result.input,
            checkpoints:result.checkpoints.map(({json,...meta})=>({...meta,sha256:sha256(json)})),
            timerLog:result.timerLog,draws:result.draws,
            final_sha256:sha256(JSON.stringify(Harness.encode(result.final)))};
}
function firstDifference(left,right,at="$") {
    if (Object.is(left,right)) return null;
    if (!left || !right || typeof left!=="object" || typeof right!=="object")
        return {path:at,left,right};
    const keys=[...new Set([...Object.keys(left),...Object.keys(right)])].sort();
    for (const key of keys) {
        const diff=firstDifference(left[key],right[key],at+"."+key);
        if (diff) return diff;
    }
    return null;
}
module.exports = {ROOT,CACHE,ORDER,sha256,inputs,config,load,run,report,firstDifference};

if (require.main === module) {
    try {
        if (process.argv.length !== 3) throw new Error("Usage: node Tools/reference/runner.cjs <trace.json>");
        const trace=JSON.parse(fs.readFileSync(process.argv[2],"utf8"));
        const {result,source}=run(trace);
        console.log(JSON.stringify(report(result,source),null,2));
    } catch (error) { console.error(error.stack); process.exitCode=1; }
}

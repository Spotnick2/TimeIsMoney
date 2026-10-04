"use strict";
// Generates Probe/Vectors.lua for the in-game probe (#9): JSMath cases with V8's
// expected results (kept only where offline Lua already matches V8 exactly) and
// the offline Lua digest of the probe's workshop run.
// node tests/reference/probe_vectors.cjs --write updates the file.
const fs=require("node:fs"), path=require("node:path"), os=require("node:os");
const {spawnSync}=require("node:child_process");
const {exactParts}=require("./workshop.cjs");
const ROOT=path.resolve(__dirname,"../.."), OUTPUT=path.join(ROOT,"Probe/Vectors.lua");
const LUA=process.env.TIM_LUA || "C:/Program Files (x86)/Lua/5.1/lua.exe";

const view=new DataView(new ArrayBuffer(8));
const words=x=>{view.setFloat64(0,x);return [view.getUint32(0),view.getUint32(4)];};
const transport=v=>Object.is(v,-0) ? "-0" : Number.isNaN(v) ? "NaN" : !Number.isFinite(v) ? String(v) : v===0 ? "0:0" : exactParts(v).join(":");
const parse=s=>s.startsWith("=") ? s.slice(1) : s==="NaN" ? NaN : s==="-0" ? -0 : s==="Infinity" ? Infinity :
    s==="-Infinity" ? -Infinity : (([m,e])=>m*2**e)(s.split(":").map(Number));

function candidates() {
    let seed=4242;
    const rnd=()=>{seed=(seed*1103515245+12345)%2147483648;return seed/2147483648;};
    const list=[];
    for (let n=-5;n<=60;n++) list.push(["pow",1.1,n]);
    for (let n=0;n<=60;n++) list.push(["pow",1.07,n]);
    for (let n=1;n<=200;n++) list.push(["pow",n,1.1]);
    for (let n=1;n<=100;n++) list.push(["pow",n,Math.E]);
    list.push(["pow",3,3.5]);
    for (let i=0;i<100;i++) list.push(["pow",0.8/(rnd()*2+0.01)*Math.pow(1.1,Math.floor(rnd()*30)),1.15]);
    let q=0;
    const seeds=[.1,.2,.3,.4,.5,.6,.7,.8,.9,1];
    for (let k=0;k<20000;k++) { q=q+.01; if (k%997===0) for (const s of seeds) list.push(["sin",q*s]); }
    for (let n=1;n<=100;n++) list.push(["sin",n]);
    for (let n=1;n<=20;n++) list.push(["sin",n*Math.PI/2]);
    for (const x of [0,-0,1e-300,Math.PI/4,823549]) list.push(["sin",x]);
    for (let n=1;n<=200;n++) list.push(["log10",n]);
    for (let i=0;i<50;i++) list.push(["log10",rnd()*Math.pow(10,Math.floor(rnd()*40-20))]);
    // Math.log: the swarm's gift rate (#13).
    for (let n=1;n<=200;n++) list.push(["log",n]);
    for (let i=0;i<50;i++) list.push(["log",rnd()*Math.pow(10,Math.floor(rnd()*40-20))]);
    let t=.5;
    for (let k=0;k<50;k++) { t=t+.01; list.push(["toString",t]); }
    for (const x of [0,1,-0.5,1e21,1.5e-7,123454288.25,1/3,5e-324,1.7976931348623157e308,0.1+0.2]) list.push(["toString",x]);
    for (let i=0;i<50;i++) list.push(["toString",Math.floor(rnd()*1e8)/100]);
    return list;
}

function luaResults(list) {
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),"tim-probe-"));
    try {
        const input=path.join(dir,"cases.txt"), output=path.join(dir,"results.txt");
        fs.writeFileSync(input,list.map(([n,x,y])=>n+" "+transport(x)+(y===undefined ? "" : " "+transport(y))).join("\n")+"\n");
        const run=spawnSync(LUA,[path.join(__dirname,"lua_math_probe.lua"),input,output],{encoding:"utf8"});
        if (run.status!==0) throw new Error(run.stderr);
        return fs.readFileSync(output,"utf8").replace(/\n$/,"").split("\n").map(parse);
    } finally { fs.rmSync(dir,{recursive:true,force:true}); }
}

function workshopDigest() {
    const script=[
        'local ns = {}',
        'assert(loadfile("Sim/Reference.lua"))("TimeIsMoneyProbe", ns)',
        'for _, path in ipairs(ns.Reference.files) do assert(loadfile(path))("TimeIsMoneyProbe", ns) end',
        'assert(loadfile("Probe/Checks.lua"))("TimeIsMoneyProbe", ns)',
        'local digest, draws, _, fields = ns.Checks.workshop(ns)',
        'local floor, floorDraws, floorFields = ns.Checks.workshopPriceFloor(ns)',
        'io.write(digest, " ", draws, " ", floor, " ", floorDraws, "\\n")',
        'local function emit(t) local k = {} for n in pairs(t) do k[#k + 1] = n end table.sort(k)',
        '  for _, n in ipairs(k) do io.write(n, "=", t[n], ";") end io.write("\\n") end',
        'emit(fields) emit(floorFields)',
    ].join("\n");
    const run=spawnSync(LUA,["-e",script],{cwd:ROOT,encoding:"utf8"});
    if (run.status!==0) throw new Error("Probe workshop run failed: "+run.stderr);
    // Windows lua.exe writes CRLF; field pairs never contain whitespace.
    const [head,fieldText,floorText]=run.stdout.split(/\r?\n/);
    const [digest,draws,floor,floorDraws]=head.trim().split(" ");
    const parse=text=>text.split(";").filter(pair=>pair.trim()!=="").map(pair=>pair.split("="));
    return {digest,draws:Number(draws),floor,floorDraws:Number(floorDraws),fields:parse(fieldText),floorFields:parse(floorText)};
}

function generate() {
    const list=candidates(), results=luaResults(list), kept=[];
    list.forEach(([name,x,y],i)=>{
        const expected=name==="toString" ? String(x) : Math[name](x,y);
        const same=name==="toString" ? results[i]===expected : Object.is(results[i],expected);
        if (same) kept.push([name,x,y,expected]);
        else if (!(name==="pow" && y===1.15)) throw new Error("Offline Lua differs from V8: "+name+"("+x+")");
    });
    const w=x=>"{"+words(x).join(",")+"}";
    const lines=kept.map(([name,x,y,expected])=>"    {"+JSON.stringify(name)+","+w(x)+","+(y===undefined ? "nil" : w(y))+","+
        (typeof expected==="string" ? JSON.stringify(expected) : w(expected))+"},");
    const {digest,draws,floor,floorDraws,fields,floorFields}=workshopDigest();
    const table=pairs=>"{ "+pairs.map(([k,v])=>"["+JSON.stringify(k)+"] = "+JSON.stringify(v)).join(", ")+" }";
    return [
        "-- Generated by tests/reference/probe_vectors.cjs; do not edit. V8 results",
        "-- (Node "+process.version+") for JSMath cases where offline Lua matches them, and the",
        "-- offline Lua 5.1 digest of Checks.workshop. Numbers are IEEE {high, low} words.",
        "local _, ns = ...",
        "ns = ns or {}",
        "ns.ProbeVectors = {",
        "  workshopDigest = "+JSON.stringify(digest)+",",
        "  workshopDraws = "+draws+",",
        "  priceFloorDigest = "+JSON.stringify(floor)+",",
        "  priceFloorDraws = "+floorDraws+",",
        "  workshopFields = "+table(fields)+",",
        "  priceFloorFields = "+table(floorFields)+",",
        "  vectors = {",
        ...lines,
        "  },",
        "}",
        "return ns.ProbeVectors",
        "",
    ].join("\n");
}
module.exports={generate,OUTPUT};

if (require.main===module) {
    const text=generate();
    if (process.argv.includes("--write")) fs.writeFileSync(OUTPUT,text);
    else process.stdout.write(text.slice(0,2000));
}

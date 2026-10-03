"use strict";
// Workshop-slice differential traces: the pinned reference in Node and the
// pure-Lua simulation run the same commands, times and recorded random stream.
const fs=require("node:fs"), path=require("node:path"), os=require("node:os");
const {spawnSync}=require("node:child_process");
const Runner=require("../../Tools/reference/runner.cjs");
const LUA=process.env.TIM_LUA || "C:/Program Files (x86)/Lua/5.1/lua.exe";

// Documented numeric exceptions (docs/reference/WORKSHOP.md). V8's Math.pow is not
// reproducible in portable Lua; the pure-Lua result can differ by one binary64 step
// for x^1.15. These two display-only fields (written by calculateRev, read only for
// presentation and saves) amplify that step to at most the measured bounds below.
// Sale quantities, eligibility, branches, timers and draws stay exact; the threshold
// test in jsmath.test.cjs proves the bounds and sale-floor insensitivity.
const TOLERANCES=[
    {path:"$.state.avgRev",maxUlps:6,reason:"calculateRev display value from Math.pow(demand, 1.15)"},
    {path:"$.state.avgSales",maxUlps:4,reason:"calculateRev display value from Math.pow(demand, 1.15)"},
];

// Explicit equidistributed fixture values (fractional parts of i times the golden
// ratio), recorded into the trace. Not a PRNG in either runner.
function stream(length=60000) {
    return Array.from({length},(_,i)=>(i*0.6180339887498949)%1);
}
const click=(at,id)=>({at,type:"click",id});
// qChip0..qChip9 with the first `active` chips switched on (project effects, #8).
const chips=active=>[.1,.2,.3,.4,.5,.6,.7,.8,.9,1].map((waveSeed,i)=>({waveSeed,value:0,active:i<active ? 1 : 0}));
const clicks=(from,count,step,id)=>Array.from({length:count},(_,i)=>click(from+i*step,id));
const traces={
    // Manual production, sales, revenue seconds, price changes and the battle core
    // past its first combat roll (960 ms).
    manual:{until:3500,commands:[...clicks(0,40,10,"btnMakePaperclip"),
        click(500,"btnRaisePrice"),click(510,"btnRaisePrice"),click(1500,"btnLowerPrice"),
        ...clicks(2000,30,20,"btnMakePaperclip")]},
    // Exact-cost purchases at funds equal to each cost, then unaffordable clicks:
    // before the next tick they run the function's own no-op branch; afterwards the
    // disabled control ignores them.
    exactCost:{until:400,fixture:{globals:{funds:125,unsoldClips:50}},commands:[
        click(0,"btnBuyWire"),click(0,"btnMakeClipper"),click(0,"btnExpandMarketing"),
        click(0,"btnMakeClipper"),click(0,"btnBuyWire"),click(0,"btnExpandMarketing"),
        click(20,"btnMakeClipper"),click(20,"btnBuyWire"),click(20,"btnExpandMarketing")]},
    // Wire depletion: partial final clicks, the disabled button and AutoClipper
    // demand larger than the remaining fraction of wire.
    depletion:{until:1200,fixture:{globals:{wire:3.2,funds:50,clipmakerLevel:150,unsoldClips:10}},
        commands:[click(0,"btnMakePaperclip"),click(0,"btnMakePaperclip"),click(30,"btnMakePaperclip"),
            click(40,"btnBuyWire")]},
    // First automation: reaching $5 announces AutoClippers; buying one starts
    // fractional production, clip-rate tracking and later purchases.
    automation:{until:3000,fixture:{globals:{funds:4.5,margin:.05,unsoldClips:200}},commands:[
        click(0,"btnMakeClipper"),click(1500,"btnMakeClipper"),click(1510,"btnMakeClipper"),
        click(1520,"btnMakeClipper"),click(2400,"btnMakeClipper")]},
    // Price floor: two lowers before the first tick reach margin 0 (infinite
    // demand), then the disabled control and recovery.
    priceFloor:{until:1300,fixture:{globals:{margin:.02,unsoldClips:400}},commands:[
        click(0,"btnLowerPrice"),click(0,"btnLowerPrice"),click(15,"btnLowerPrice"),
        click(1050,"btnRaisePrice"),click(1060,"btnRaisePrice")]},
    // Milestones and trust: message text, timeCruncher and the Fibonacci target.
    milestones:{until:300,fixture:{globals:{clipmakerLevel:5000,ticks:372150,nextTrust:600,funds:5}},commands:[]},
    // MegaClipper purchase (the hidden button still clicks, as in the browser host).
    mega:{until:800,fixture:{globals:{funds:1200,megaClipperFlag:1}},commands:[
        click(0,"btnMakeMegaClipper"),click(0,"btnMakeMegaClipper"),click(100,"btnMakeMegaClipper")]},
    // Reachable cent prices where the pow step reaches the display fields
    // (found by the #32 review): margin 10.06 and margin 1.50 with marketing level 4.
    highPrice:{until:1000,fixture:{globals:{margin:10.06,marketingLvl:1,unsoldClips:10}},commands:[]},
    pricedMarketing:{until:2000,fixture:{globals:{margin:1.5,marketingLvl:4,unsoldClips:200}},commands:[]},
    // No input, money or stock enables Operations: Beg for More Wire and the
    // projects list appear in the same tick, then Operations accumulate.
    computationUnlock:{until:1500,fixture:{globals:{wire:0.5,funds:1,unsoldClips:0}},commands:[
        click(0,"btnMakePaperclip")]},
    // Trust allocation: clicks before the next tick can exceed trust (the control
    // disables only at buttonUpdate); then the memory cap and "Need Photonic Chips".
    allocation:{until:1500,fixture:{globals:{compFlag:1,trust:7,standardOps:1980}},commands:[
        ...clicks(0,4,0,"btnAddProc"),click(0,"btnAddMem"),click(0,"btnAddMem"),
        click(30,"btnAddMem"),click(40,"btnQcompute")]},
    // Creativity at full Operations: whole increments (check >= 1), then the
    // creativity projects; and fractional increments (check < 1) at high speed.
    creativity:{until:3200,fixture:{globals:{compFlag:1,creativityOn:1,trust:100,processors:29,standardOps:1000}},
        commands:[click(0,"btnAddProc")]},
    creativityFast:{until:1000,fixture:{globals:{compFlag:1,creativityOn:1,trust:500,processors:399,standardOps:1000}},
        commands:[click(0,"btnAddProc")]},
    // Temporary Operations above memory fade once opFadeTimer passes its delay.
    opFade:{until:1200,fixture:{globals:{compFlag:1,standardOps:600,tempOps:900,opFade:.01,opFadeTimer:790}},
        commands:[]},
    // Quantum chips oscillate with the shared clock; qComp adds positive sums and
    // overflows into temporary Operations.
    quantumOverflow:{until:1500,fixture:{globals:{compFlag:1,qFlag:1,qClock:1.2,standardOps:700,
        qChips:chips(7)}},commands:[click(0,"btnQcompute"),click(200,"btnQcompute"),click(210,"btnQcompute"),
        click(900,"btnQcompute")]},
    // A negative chip sum drains Operations below zero; at -10,000 the Operations
    // recovery project appears, and processors slowly refill.
    // Clicks at t=0 come before the first quantum tick, so every chip value is still 0.
    quantumNegative:{until:1200,fixture:{globals:{compFlag:1,qFlag:1,qClock:60,standardOps:500,
        qChips:chips(10)}},commands:[click(0,"btnQcompute"),...clicks(50,4,10,"btnQcompute"),click(500,"btnQcompute")]},
};
function make(name) {
    if (!Object.hasOwn(traces,name)) throw new Error("Unknown workshop trace: "+name);
    const trace=JSON.parse(JSON.stringify(traces[name]));
    trace.random=stream(); trace.drawing=true;
    return trace;
}
// An exact integer mantissa and binary exponent for a finite double, so Lua
// rebuilds the same value with math.ldexp instead of parsing decimal text (some C
// runtimes misround decimal halfway cases).
function exactParts(value) {
    const view=new DataView(new ArrayBuffer(8));
    view.setFloat64(0,Math.abs(value));
    const bits=view.getBigUint64(0), biased=Number(bits>>52n);
    let mantissa=bits&((1n<<52n)-1n), exponent;
    if (biased===0) exponent=-1074; else {mantissa|=1n<<52n; exponent=biased-1075;}
    while (mantissa!==0n && (mantissa&1n)===0n) {mantissa>>=1n; exponent++;}
    return [(value<0 || Object.is(value,-0) ? "-" : "")+mantissa.toString(),exponent];
}
function toLua(value) {
    if (typeof value==="number") {
        if (!Number.isFinite(value) || Object.is(value,-0)) throw new Error("Unsupported trace number");
        if (Number.isInteger(value) && Math.abs(value)<2**53) return String(value);
        const [mantissa,exponent]=exactParts(value);
        return "L("+mantissa+","+exponent+")";
    }
    if (typeof value==="string") {
        if (!/^[\x20-\x7e]*$/.test(value)) throw new Error("Trace strings must be printable ASCII");
        return JSON.stringify(value);
    }
    if (typeof value==="boolean") return String(value);
    if (Array.isArray(value)) return "{"+value.map(toLua).join(",")+"}";
    return "{"+Object.entries(value).map(([k,v])=>"["+JSON.stringify(k)+"]="+toLua(v)).join(",")+"}";
}
function lua(trace) {
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),"tim-lua-trace-"));
    try {
        const input=path.join(dir,"trace.lua"), output=path.join(dir,"trace.json");
        const {random,fixture,commands,until}=trace;
        fs.writeFileSync(input,"local L = math.ldexp; return "+toLua({random,fixture:fixture||{},commands:commands||[],until}));
        const out=spawnSync(LUA,[path.join(__dirname,"lua_trace_runner.lua"),input,output],{encoding:"utf8",maxBuffer:64*1024*1024});
        if (out.status!==0) throw new Error("Lua trace runner failed: "+out.stderr);
        return JSON.parse(fs.readFileSync(output,"utf8"));
    } finally { fs.rmSync(dir,{recursive:true,force:true}); }
}
// Runs both sides; returns the documents and the first divergence (or null).
function compare(name, source=Runner.inputs()) {
    const trace=make(name);
    const reference=Runner.report(Runner.run(trace,source).result,source,true);
    const port=lua(trace);
    let left=Runner.project(reference,port.projection);
    if (port.error) {
        // Compare the agreed prefix up to the Lua slice's explicit stop.
        left={...left,events:left.events.slice(0,port.events.length),
            checkpoints:left.checkpoints.slice(0,port.checkpoints.length)};
    }
    const tolerated=[];
    const divergence=Runner.compare(left,port,source,{tolerances:TOLERANCES,onTolerated:item=>tolerated.push(item)});
    return {trace,reference,port,divergence,tolerated};
}
module.exports={names:Object.keys(traces),make,lua,compare,stream,exactParts,LUA,TOLERANCES};

if (require.main===module) {
    for (const name of process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(traces)) {
        const t0=Date.now(), {port,divergence,tolerated}=compare(name);
        const d=divergence && {kind:divergence.kind,event:divergence.event,ordinal:divergence.ordinal,
            checkpoint:divergence.checkpoint,after:divergence.after,field:divergence.field,
            difference:divergence.difference,left:divergence.left,right:divergence.right};
        console.log(name,(Date.now()-t0)+"ms","events",port.events.length,"error",port.error,"tolerated",tolerated.length,
            divergence ? "DIVERGES "+JSON.stringify(d) : "matches");
    }
}

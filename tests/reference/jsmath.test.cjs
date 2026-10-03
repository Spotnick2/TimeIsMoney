"use strict";
// Measures the pure-Lua Math.pow (Sim/JSMath.lua) against V8 in this Node profile.
// Integer exponents (costs, marketing) must match exactly; fractional exponents may
// differ by one binary64 step only where V8 itself is not correctly rounded.
const test=require("node:test"), assert=require("node:assert/strict");
const fs=require("node:fs"), path=require("node:path"), os=require("node:os");
const {spawnSync}=require("node:child_process");
const {ulps}=require("../../Tools/reference/host.js");
const {LUA,exactParts}=require("./workshop.cjs");

// Exact transport: "mantissa:exponent" pairs, so no decimal parsing is involved.
const tokens={NaN:NaN,Infinity:Infinity,"-Infinity":-Infinity,"-0":-0};
function text(v) {
    if (Object.is(v,-0)) return "-0";
    if (!Number.isFinite(v)) return String(v);
    if (v===0) return "0:0";
    return exactParts(v).join(":");
}
function parse(s) {
    if (Object.hasOwn(tokens,s)) return tokens[s];
    const [mantissa,exponent]=s.split(":").map(Number);
    return mantissa*2**exponent;
}

function cases() {
    let seed=12345;
    const rnd=()=>{seed=(seed*1103515245+12345)%2147483648;return seed/2147483648;};
    const list=[];
    for (let n=-5;n<=400;n++) list.push([1.1,n,"integer"],[1.07,n,"integer"]);
    for (let i=0;i<20000;i++) list.push([rnd()*1000,1.15,"fraction"],[0.8/(rnd()*2+0.01)*Math.pow(1.1,Math.floor(rnd()*30)),1.15,"fraction"]);
    for (let i=0;i<8000;i++) {
        const x=(rnd()-0.3)*Math.pow(10,Math.floor(rnd()*40-20));
        const integral=rnd()<0.3, y=integral ? Math.floor((rnd()-0.5)*60) : (rnd()-0.5)*Math.pow(10,Math.floor(rnd()*6-3));
        list.push([x,y,integral ? "integer" : "fraction"]);
    }
    const special=[0,-0,1,-1,0.5,-0.5,2,-2,3,-3,Infinity,-Infinity,NaN,1e308,1e-300,1.15];
    for (const a of special) for (const b of special) list.push([a,b,"special"]);
    return list;
}

test("pure-Lua Math.pow matches V8 for integer exponents and specials, within V8's own rounding elsewhere",t=>{
    const list=cases(), dir=fs.mkdtempSync(path.join(os.tmpdir(),"tim-pow-"));
    try {
        const input=path.join(dir,"pairs.txt"), output=path.join(dir,"results.txt");
        fs.writeFileSync(input,list.map(([x,y])=>text(x)+" "+text(y)).join("\n")+"\n");
        const run=spawnSync(LUA,[path.join(__dirname,"lua_pow_probe.lua"),input,output],{encoding:"utf8"});
        assert.equal(run.status,0,run.stderr);
        const results=fs.readFileSync(output,"utf8").trim().split("\n").map(parse);
        assert.equal(results.length,list.length);
        const counts={integer:[0,0],fraction:[0,0],special:[0,0]};
        for (const [i,[x,y,kind]] of list.entries()) {
            const expected=Math.pow(x,y), actual=results[i];
            counts[kind][0]++;
            if (Object.is(expected,actual)) continue;
            // Subnormal results are outside the reference's ranges and not claimed.
            if (Math.abs(expected)<2.2250738585072014e-308 && expected!==0) continue;
            counts[kind][1]++;
            assert.notEqual(kind,"integer","x="+x+" y="+y+" V8 "+expected+" Lua "+actual);
            assert.notEqual(kind,"special","x="+x+" y="+y+" V8 "+expected+" Lua "+actual);
            assert.equal(ulps(expected,actual),1,"x="+x+" y="+y);
        }
        // Measured 2026-10-03 on Node v24.15.0 / Windows: 18 of 45,415 fractional cases.
        assert.ok(counts.fraction[1]<=counts.fraction[0]*0.001,JSON.stringify(counts));
        t.diagnostic("cases and one-step differences: "+JSON.stringify(counts));
    } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});

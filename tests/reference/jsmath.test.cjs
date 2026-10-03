"use strict";
// Measures Sim/JSMath.lua against V8 in this Node profile. Math.sin and Math.log10
// (fdlibm ports) must match exactly. Math.pow integer exponents (costs, marketing)
// and processor counts up to the verified bound must match exactly; other
// fractional exponents may differ by one binary64 step only where V8 itself is not
// correctly rounded.
const test=require("node:test"), assert=require("node:assert/strict");
const fs=require("node:fs"), path=require("node:path"), os=require("node:os");
const {spawnSync}=require("node:child_process");
const {ulps}=require("../../Tools/reference/host.js");
const {LUA,exactParts,TOLERANCES}=require("./workshop.cjs");

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

// Evaluates [name, x, y?] cases with Sim/JSMath.lua and returns the results.
function luaMath(cases, keepText=false) {
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),"tim-math-"));
    try {
        const input=path.join(dir,"cases.txt"), output=path.join(dir,"results.txt");
        fs.writeFileSync(input,cases.map(([name,x,y])=>name+" "+text(x)+(y===undefined ? "" : " "+(typeof y==="string" ? y : text(y)))).join("\n")+"\n");
        const run=spawnSync(LUA,[path.join(__dirname,"lua_math_probe.lua"),input,output],{encoding:"utf8"});
        assert.equal(run.status,0,run.stderr);
        const results=fs.readFileSync(output,"utf8").replace(/\n$/,"").split("\n").map(line=>line.startsWith("=") ? line.slice(1) : parse(line));
        assert.equal(results.length,cases.length);
        return results;
    } finally { fs.rmSync(dir,{recursive:true,force:true}); }
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
    const list=cases(), results=luaMath(list.map(([x,y])=>["pow",x,y]));
    {
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
    }
});

test("fdlibm Math.sin and Math.log10 match V8 exactly, including the quantum clock and wire price",t=>{
    let seed=777;
    const rnd=()=>{seed=(seed*1103515245+12345)%2147483648;return seed/2147483648;};
    const list=[], seeds=[.1,.2,.3,.4,.5,.6,.7,.8,.9,1];
    // qClock accumulates .01 per tick; chips evaluate qClock * waveSeed * active.
    let q=0;
    for (let k=0;k<100000;k++) { q=q+.01; if (k%23===0) for (const s of seeds) list.push(["sin",q*s*1]); }
    for (let n=1;n<=5000;n++) list.push(["sin",n],["sin",-n]); // wirePriceCounter
    for (let n=1;n<=2000;n++) for (const d of [-1,0,1]) list.push(["sin",n*Math.PI/2+d*1e-9]);
    // Arguments one or more high words away from n*pi/2, where V8's reduction takes
    // the npio2_hw quick path (n < 32) instead of the refinement passes.
    const view=new DataView(new ArrayBuffer(8));
    const high=x=>{view.setFloat64(0,x);return view.getUint32(0);};
    const fromWords=(h,l)=>{view.setUint32(0,h>>>0);view.setUint32(4,l>>>0);return view.getFloat64(0);};
    for (let n=1;n<=40;n++) for (const d of [1,2,8,16,-1,-2,-8,-16]) for (const low of [0,0x80000000,0xffffffff]) {
        const x=fromWords(high(n*Math.PI/2)+d,low);
        list.push(["sin",x],["sin",-x]);
    }
    for (let i=0;i<20000;i++) list.push(["sin",(rnd()-0.5)*2*Math.pow(10,Math.floor(rnd()*11-5))]);
    for (const x of [0,-0,1e-300,-1e-300,5e-324,Math.PI/4,Math.PI/2,3*Math.PI/4,Infinity,-Infinity,NaN,823549,-823549])
        list.push(["sin",x]);
    for (let n=1;n<=20000;n++) list.push(["log10",n]);
    for (let i=0;i<20000;i++) list.push(["log10",rnd()*Math.pow(10,Math.floor(rnd()*600-300))]);
    for (const x of [0,-0,-1,1,10,0.1,5e-324,2.2250738585072014e-308,1e308,Infinity,-Infinity,NaN]) list.push(["log10",x]);
    const results=luaMath(list);
    for (const [i,[name,x]] of list.entries()) {
        const expected=Math[name](x);
        assert.ok(Object.is(expected,results[i]),name+"("+x+") V8 "+expected+" Lua "+results[i]);
    }
    t.diagnostic("exact cases: "+list.length);
});

test("Math.pow(processors, 1.1) matches V8 for every count up to the verified bound",()=>{
    const bound=3424, list=[];
    for (let n=1;n<=bound+1;n++) list.push(["pow",n,1.1],["log10",n]);
    const results=luaMath(list);
    for (let n=1;n<=bound;n++) {
        assert.ok(Object.is(results[2*n-2],Math.pow(n,1.1)),"pow("+n+", 1.1)");
        assert.ok(Object.is(results[2*n-1],Math.log10(n)),"log10("+n+")");
    }
    // The first known difference, which Sim/Workshop.lua refuses to cross.
    assert.equal(ulps(results[2*bound],Math.pow(bound+1,1.1)),1);
});

// Threshold evidence for the workshop's numeric exception: over every reachable
// demand in this slice (cent prices up to $100, marketing levels 1-60, slice
// constants for effectiveness, boost and prestige), a one-step change in
// Math.pow(demand, 1.15) never changes a sale quantity and moves the display
// fields by no more than the declared bounds.
test("a one-step pow difference cannot change sale quantities and stays within the declared bounds",t=>{
    const view=new DataView(new ArrayBuffer(8));
    const neighbor=(x,d)=>{view.setFloat64(0,x);view.setBigUint64(0,view.getBigUint64(0)+BigInt(d));return view.getFloat64(0);};
    const bound=Object.fromEntries(TOLERANCES.map(t=>[t.path,t.maxUlps]));
    let cases=0, maxSales=0, maxRev=0;
    for (let cents=1;cents<=10000;cents++) {
        const margin=cents/100;
        for (let level=1;level<=60;level++) {
            let demand=(((.8/margin)*Math.pow(1.1,level-1)*1)*1);
            demand=demand+((demand/10)*0);
            const p=Math.pow(demand,1.15), chance=Math.min(demand/100,1);
            for (const q of [neighbor(p,-1),neighbor(p,1)]) {
                cases++;
                assert.equal(Math.floor(.7*q),Math.floor(.7*p),"sale floor at margin "+margin+" level "+level);
                maxSales=Math.max(maxSales,ulps(chance*(.7*p)*10,chance*(.7*q)*10));
                maxRev=Math.max(maxRev,ulps(chance*(.7*p)*margin*10,chance*(.7*q)*margin*10));
            }
        }
    }
    assert.ok(maxSales<=bound["$.state.avgSales"] && maxRev<=bound["$.state.avgRev"]);
    t.diagnostic("neighbor cases "+cases+"; max steps avgSales "+maxSales+", avgRev "+maxRev);
});

test("Number::toString matches V8 exactly without the C library",t=>{
    let seed=11;
    const rnd=()=>{seed=(seed*1103515245+12345)%2147483648;return seed/2147483648;};
    const values=[0.5400000000000001,0.51,1,100,1e21,1.5e21,123456789012345680000,1e-7,1.5e-7,1e-6,1.2e-6,-0.5,
        5e-324,2.2250738585072014e-308,1.7976931348623157e308,0.1+0.2,1/3,-1234567.891,2**53+2,2**60,1e23,
        12823867.7978515625,-497002601623535170];
    let threshold=.5;
    for (let k=0;k<200;k++) { threshold=threshold+.01; values.push(threshold); } // stockGainThreshold
    for (let i=0;i<6000;i++) values.push((rnd()-0.5)*Math.pow(10,Math.floor(rnd()*60-30)));
    for (let i=0;i<2000;i++) values.push(Math.floor(rnd()*1e6)/100);
    for (let i=0;i<1000;i++) values.push(Math.pow(2,Math.floor(rnd()*2000-1074)));
    const results=luaMath(values.map(x=>["toString",x]));
    values.forEach((x,i)=>assert.equal(results[i],String(x),"toString("+x+")"));
    t.diagnostic("exact cases: "+values.length);
});

test("formatWithCommas matches the reference function",()=>{
    const Runner=require("../../Tools/reference/runner.cjs"), Workshop=require("./workshop.cjs");
    const reference=Runner.load(Workshop.make("milestones"),Runner.inputs()).global.formatWithCommas;
    const values=[0,1,999,1000,-1000,12345.678,123456789,123454288.25,-2500.75,1e21,1.5e21,2.5e22,1234.5,0.001,
        999.999,1000000.5,NaN,1e-7,987654321.123];
    const cases=[];
    for (const x of values) for (const decimal of [undefined,0,2]) cases.push(["formatWithCommas",x,decimal===undefined ? undefined : String(decimal)]);
    const results=luaMath(cases);
    cases.forEach(([,x,decimal],i)=>{
        const expected=decimal===undefined ? reference(x) : reference(x,Number(decimal));
        assert.equal(results[i],expected,"formatWithCommas("+x+", "+decimal+")");
    });
});

test("Math.pow(level, Math.E) matches V8 for every investment level below the verified bound",()=>{
    const bound=967, list=[];
    for (let n=1;n<=bound+1;n++) list.push(["pow",n,Math.E]);
    const results=luaMath(list);
    for (let n=1;n<=bound;n++) assert.ok(Object.is(results[n-1],Math.pow(n,Math.E)),"pow("+n+", e)");
    assert.equal(ulps(results[bound],Math.pow(bound+1,Math.E)),1,"first known difference");
});

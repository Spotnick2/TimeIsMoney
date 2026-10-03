"use strict";
// Issue #5 acceptance: the pure-Lua workshop slice agrees with the pinned reference
// after every command and callback, including every timer event and labeled draw.
const test=require("node:test"), assert=require("node:assert/strict");
const Runner=require("../../Tools/reference/runner.cjs"), Workshop=require("./workshop.cjs");
const source=Runner.inputs();
const results={};
const run=name=>results[name] ??= Workshop.compare(name,source);
const points=port=>port.checkpoints.map(point=>({...point,...JSON.parse(point.json)}));
const command=(port,at,id,nth=0)=>points(port).filter(p=>p.kind==="command" && p.at===at && p.id===id)[nth];
const final=port=>points(port).at(-1);

for (const name of Workshop.names) test("workshop "+name+" trace agrees with the reference at every checkpoint",()=>{
    const {port,divergence}=run(name);
    assert.equal(divergence,null,JSON.stringify(divergence && {kind:divergence.kind,event:divergence.event,
        field:divergence.field,difference:divergence.difference,left:divergence.left,right:divergence.right}));
    assert.deepEqual(port.source_sha256,source.index.source_sha256);
    if (name!=="computationBoundary") assert.equal(port.error,null);
});

test("exact costs buy at equal funds; unaffordable clicks run no-op branches, then controls disable",()=>{
    const {port}=run("exactCost");
    const wire=command(port,0,"btnBuyWire").state, clipper=command(port,0,"btnMakeClipper").state;
    const ads=command(port,0,"btnExpandMarketing").state;
    assert.deepEqual([wire.funds,wire.wire,wire.wirePurchase],[105,2000,1]);
    assert.deepEqual([clipper.funds,clipper.clipmakerLevel,clipper.clipperCost],[100,1,6.1]);
    assert.deepEqual([ads.funds,ads.marketingLvl,ads.adCost],[0,2,200]);
    const noop=command(port,0,"btnMakeClipper",1).state;
    assert.deepEqual([noop.funds,noop.clipmakerLevel,noop.clipperCost],[0,1,6.1]);
    const later=command(port,20,"btnMakeClipper");
    assert.equal(later.dom.btnMakeClipper.disabled,true);
    assert.equal(later.dom.btnBuyWire.disabled,true);
    assert.equal(later.state.clipmakerLevel,1);
});
test("wire depletes exactly, AutoClipper demand clamps to the remainder, and restocking resumes",()=>{
    const {port}=run("depletion");
    const empty=command(port,30,"btnMakePaperclip");
    assert.equal(empty.state.wire,0);
    assert.equal(empty.dom.btnMakePaperclip.disabled,true);
    assert.equal(empty.state.clips,3.2,"two clicks plus a 1.2 clamp of the 1.5 AutoClipper demand");
    const restock=command(port,40,"btnBuyWire").state;
    assert.deepEqual([restock.wire,restock.funds],[1000,30]);
    assert.ok(final(port).state.clips>empty.state.clips);
});
test("first automation: $5 announces AutoClippers; the first purchase starts fractional production",()=>{
    const {port}=run("automation");
    const first=command(port,0,"btnMakeClipper").state;
    assert.deepEqual([first.clipmakerLevel,first.clipperCost],[0,6],"an unaffordable click recomputes 1.1^0+5");
    const announced=points(port).find(p=>p.dom.readout1.html==="AutoClippers available for purchase");
    assert.ok(announced && announced.state.funds>=5 && announced.state.autoClipperFlag===1);
    const blocked=command(port,1500,"btnMakeClipper");
    assert.deepEqual([blocked.state.clipmakerLevel,blocked.dom.btnMakeClipper.disabled],[0,true]);
    const bought=command(port,2400,"btnMakeClipper").state;
    assert.equal(bought.clipmakerLevel,1);
    const end=final(port).state;
    assert.ok(end.clips>0 && end.clips<1 && end.clipRate>0);
    assert.deepEqual(end.activeProjects.map(p=>p.id),["projectButton1"]);
});
test("a zero price yields NaN demand and stops sales until the price recovers",()=>{
    const {port}=run("priceFloor");
    const zero=command(port,15,"btnLowerPrice");
    assert.equal(zero.state.margin,0);
    assert.deepEqual(zero.state.demand,{$number:"NaN"});
    assert.equal(zero.dom.btnLowerPrice.disabled,true);
    const end=final(port).state;
    assert.deepEqual([end.margin,end.demand],[0.02,40]);
    assert.ok(end.unsoldClips<400);
});
test("milestones, trust and time text follow the reference",()=>{
    const {port}=run("milestones");
    const end=final(port);
    assert.equal(end.state.milestoneFlag,3);
    const messages=[1,2,3,4,5].map(i=>end.dom["readout"+i].html);
    assert.ok(messages.includes("1,000 clips created in 1 hour 2 minutes 1 second"),messages.join(" | "));
    assert.ok(messages.includes("500 clips created in 1 hour 2 minutes 1 second"));
    assert.ok(messages.includes("AutoClippers available for purchase"));
    assert.ok(messages.some(m=>m.startsWith("Production target met")));
    assert.deepEqual([end.state.fib1,end.state.fib2],[3,5]);
});
test("MegaClipper purchases and recomputed costs match",()=>{
    const {port}=run("mega");
    const bought=command(port,0,"btnMakeMegaClipper").state;
    assert.deepEqual([bought.megaClipperLevel,bought.funds],[1,700]);
    assert.equal(command(port,0,"btnMakeMegaClipper",1).state.megaClipperLevel,1);
    assert.equal(command(port,100,"btnMakeMegaClipper").dom.btnMakeMegaClipper.disabled,true);
});
test("the slice stops explicitly where Operations begins (#6)",()=>{
    const {port,reference}=run("computationBoundary");
    assert.match(port.error,/Unported reference path: calculateOperations \(issue #6\)/);
    // The reference continues; the agreed prefix ends at the Lua stop.
    assert.ok(reference.events.length>port.events.length);
});
test("the battle core is exercised beyond its first combat roll",()=>{
    const {port}=run("manual");
    const combat=port.events.filter(e=>e.action==="draw" && /^combat\.js:51[05]:/.test(e.site));
    assert.ok(combat.length>1000,"combat rolls: "+combat.length);
    const sales=port.events.filter(e=>e.action==="draw" && e.site==="main.js:4574:18");
    assert.ok(sales.length>=30);
    assert.ok(final(port).state.clipsSold>0);
});

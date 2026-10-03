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
    assert.equal(port.error,null);
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
test("the battle core is exercised beyond its first combat roll",()=>{
    const {port}=run("manual");
    const combat=port.events.filter(e=>e.action==="draw" && /^combat\.js:51[05]:/.test(e.site));
    assert.ok(combat.length>1000,"combat rolls: "+combat.length);
    const sales=port.events.filter(e=>e.action==="draw" && e.site==="main.js:4574:18");
    assert.ok(sales.length>=30);
    assert.ok(final(port).state.clipsSold>0);
});
test("reachable prices use only the declared display-field exception, never elsewhere",()=>{
    for (const name of Workshop.names) for (const item of run(name).tolerated)
        assert.ok(["$.state.avgRev","$.state.avgSales"].includes(item.path),name+" "+item.path);
    const {tolerated,port,trace}=run("highPrice");
    assert.ok(tolerated.some(item=>item.path==="$.state.avgRev" && item.ulps>=1));
    assert.ok(run("pricedMarketing").tolerated.some(item=>item.path==="$.state.avgSales"));
    // Without the exception the reference comparison reports the one-step difference.
    const reference=Runner.report(Runner.run(trace,source).result,source,true);
    const exact=Runner.compare(Runner.project(reference,port.projection),port,source);
    assert.deepEqual([exact.kind,exact.difference.path,exact.difference.ulps],["state","$.state.avgRev",1]);
});

// Issue #6 boundaries: allocation and capacity, unlocks, creativity, quantum chips
// and negative Operations, all inside the exact comparisons above.
const states=port=>points(port).map(p=>p.state);
test("running out of input, money and stock unlocks Operations and two projects in one tick",()=>{
    const {port}=run("computationUnlock");
    const unlocked=points(port).find(p=>p.state.compFlag===1);
    assert.equal(unlocked.dom.readout1.html,"Trust-Constrained Self-Modification enabled");
    assert.deepEqual(unlocked.state.activeProjects.map(p=>p.id),["projectButton2","projectButton42"]);
    assert.ok(final(port).state.operations>0);
});
test("trust allocation can exceed trust before the next tick; then controls disable and memory caps Operations",()=>{
    const {port}=run("allocation");
    const memory=command(port,0,"btnAddMem",1).state;
    assert.deepEqual([memory.processors,memory.memory,memory.trust],[5,3,7],"8 allocated against 7 trust");
    assert.equal(command(port,0,"btnAddProc").state.creativitySpeed,1.6452719215601408);
    const late=command(port,30,"btnAddMem");
    assert.deepEqual([late.state.memory,late.dom.btnAddMem.disabled,late.dom.btnAddProc.disabled],[3,true,true]);
    const noChips=command(port,40,"btnQcompute").state;
    assert.equal(noChips.qFade,1,"qComp without photonic chips only resets the fade");
    const end=final(port).state;
    assert.ok(end.standardOps<=end.memory*1000);
    assert.ok(end.activeProjects.some(p=>p.id==="projectButton50"),"processors >= 5");
});
test("creativity accrues whole points, then fractional points, and unlocks the creativity projects",()=>{
    const slow=run("creativity").port, fast=run("creativityFast").port;
    const slowEnd=final(slow).state, fastEnd=final(fast).state;
    assert.equal(command(slow,0,"btnAddProc").state.creativitySpeed,91.26579357925937);
    assert.ok(Number.isInteger(slowEnd.creativity) && slowEnd.creativity>=50);
    assert.ok(slowEnd.activeProjects.some(p=>p.id==="projectButton13"));
    assert.equal(command(fast,0,"btnAddProc").state.creativitySpeed,2293.8869097352176);
    assert.ok(!Number.isInteger(fastEnd.creativity) && fastEnd.creativity>250);
    const ids=fastEnd.activeProjects.map(p=>p.id);
    for (const id of ["13","14","15","17","19"]) assert.ok(ids.includes("projectButton"+id),id);
    assert.match(command(fast,0,"btnAddProc").dom.readout1.html,/operations \(or creativity\)/);
});
test("temporary Operations fade once opFadeTimer passes its delay",()=>{
    const all=states(run("opFade").port).slice(1); // from the fixture onward
    assert.ok(all.some(s=>s.opFade>1),"fade accelerates past opFadeDelay");
    assert.ok(all.at(-1).tempOps<900 && all.at(-1).tempOps>0);
    for (let i=1;i<all.length;i++) assert.ok(all[i].tempOps<=all[i-1].tempOps);
});
test("quantum chips oscillate with the clock and qComp overflows into temporary Operations",()=>{
    const {port}=run("quantumOverflow");
    const all=states(port);
    const values=new Set(all.map(s=>s.qChips[0].value));
    assert.ok(values.size>100,"chip values change every tick");
    assert.ok(all.every(s=>s.qChips[9].value===0),"inactive chips stay 0");
    const overflow=command(port,200,"btnQcompute").state;
    assert.equal(overflow.standardOps,1000);
    assert.ok(overflow.tempOps<0,"the reference can make tempOps negative on overflow");
    assert.ok(final(port).state.tempOps>0);
    // The reference report records the injected fixture, not values the run mutated.
    const {reference,trace}=run("quantumOverflow");
    assert.ok(reference.input.fixture.globals.qChips.every(chip=>chip.value===0));
    assert.ok(trace.fixture.globals.qChips.every(chip=>chip.value===0));
});
test("a negative chip sum drives Operations below -10,000 and unlocks the recovery project",()=>{
    const {port}=run("quantumNegative");
    assert.equal(command(port,0,"btnQcompute").state.standardOps,500,"no chip values before the first tick");
    const end=final(port).state;
    assert.ok(end.operations<=-10000,String(end.operations));
    assert.ok(end.activeProjects.some(p=>p.id==="projectButton217"));
    assert.ok(Math.min(...states(port).map(s=>s.standardOps))<-12000);
});

// Issue #7 boundaries: investments and tournaments.
test("deposits buy generated-symbol stocks whose prices gain and lose",()=>{
    const all=states(run("investments").port), end=all.at(-1);
    assert.equal(Math.max(...all.map(s=>s.portfolioSize)),3);
    assert.ok(end.stocks.every(stock=>/^[A-Z]{1,4}$/.test(stock.symbol)));
    assert.ok(end.stocks.some(stock=>stock.profit>0) && end.stocks.some(stock=>stock.profit<0));
    assert.equal(end.riskiness,5,"med risk");
    assert.ok(end.bankroll<20000);
});
test("a held stock is sold after sellDelay reaches five",()=>{
    const all=states(run("investmentSale").port);
    assert.equal(Math.max(...all.map(s=>s.portfolioSize)),1);
    assert.deepEqual([all.at(-1).portfolioSize,all.at(-1).stockID],[0,1]);
});
test("high risk spends the whole bankroll; an unknown risk empties the select; withdrawal",()=>{
    const {port}=run("investmentRisk"), all=points(port);
    assert.ok(all.some(p=>p.state.riskiness===1 && p.state.portfolioSize===1 && p.state.bankroll===0));
    const bogus=command(port,2100,"investStrat");
    assert.equal(bogus.dom.investStrat.value,"");
    const withdrawn=command(port,4100,"btnWithdraw").state;
    assert.equal(withdrawn.bankroll,0);
    assert.equal(withdrawn.riskiness,1);
});
test("engine upgrades can overspend Yomi before the next tick, then disable",()=>{
    const {port}=run("investUpgrade"), end=final(port).state;
    assert.deepEqual([end.yomi,end.investLevel,end.investUpgradeCost],[-258,2,1981]);
    assert.equal(end.stockGainThreshold,0.52);
    const messages=[1,2].map(i=>final(port).dom["readout"+i].html);
    assert.deepEqual(messages,["Investment engine upgraded, expected profit/loss ratio now 0.52",
        "Investment engine upgraded, expected profit/loss ratio now 0.51"]);
    assert.equal(command(port,50,"btnImproveInvestments").dom.btnImproveInvestments.disabled,true);
});
test("the lifetime investment report formats ledger plus portfolio",()=>{
    const {port}=run("investReport");
    assert.ok(points(port).some(p=>p.dom.readout1.html==="Lifetime investment revenue report: $123,454,288"));
});
test("tournaments score every strategy pair and award Yomi to the picked strategy",()=>{
    for (const name of ["tourneyGreedy","tourneyMinimax","tourneyBeatLast","tourneyFixed"]) {
        const {port}=run(name), end=final(port);
        assert.deepEqual([end.state.tourneyInProg,end.state.resultsFlag,end.state.tourneyLvl],[0,1,2],name);
        assert.ok(end.state.yomi>0,name);
        assert.match(end.dom.readout1.html,/ scored \d+ and beat \d+ strats?\. Yomi increased by \d+$/,name);
        assert.equal(end.state.results.length,2,name);
        assert.ok(end.state.activeProjects.some(p=>p.id==="projectButton27"),name+": Yomi unlocks");
    }
    assert.ok(states(run("tourneyMinimax").port).some(s=>s.w!==undefined),"TIT FOR TAT writes w");
    // The implicit loop globals i and n are compared like any other state.
    const projected=run("tourneyGreedy").port.projection.state;
    assert.ok(projected.includes("i") && projected.includes("n"));
    assert.equal(final(run("tourneyGreedy").port).state.n,2);
    const greedy=run("tourneyGreedy").port;
    assert.equal(command(greedy,40,"btnRunTournament").state.currentRound,0,"Run disables while running");
});
test("automatic tournaments restart from shown results; without a pick nothing is awarded",()=>{
    const auto=final(run("autoTourney").port);
    assert.equal(auto.state.tourneyLvl,3);
    assert.equal(points(run("autoTourney").port).filter(p=>p.kind==="callback" && /scored/.test(p.dom.readout1.html))
        .map(p=>p.dom.readout1.html).filter((m,i,a)=>a.indexOf(m)===i).length,2);
    const none=final(run("noPick").port).state;
    assert.deepEqual([none.tourneyInProg,none.resultsFlag,none.yomi],[0,0,0]);
});

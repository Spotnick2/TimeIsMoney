"use strict";
// Issue #5 acceptance: the pure-Lua workshop slice agrees with the pinned reference
// after every command and callback, including every timer event and labeled draw.
const test=require("node:test"), assert=require("node:assert/strict");
const Runner=require("../../Tools/reference/runner.cjs"), Workshop=require("./workshop.cjs");
const source=Runner.inputs();
const results={};
// Only what the assertions read is cached: the reference documents of all traces
// together exceed the default heap.
const run=name=>results[name] ??= (({trace,reference,port,divergence,tolerated})=>
    ({trace,reference:{input:reference.input},port,divergence,tolerated}))(Workshop.compare(name,source));
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

// Issue #8: phase-one projects and the first transition.
const PROJECT_RUNS=["projectsProduction","projectsCreativity","projectsStrategy","projectsBusiness",
    "projectsVolition","projectsMachines","projectsRecovery","projectsLate","transition",
    "planetChain","planetPipeline","planetUpgrades","swarmGifts","spaceGate","spaceProjects","battleVictory",
    "correspondence","memorials","memoryRelease","endingReject","endingAccept","endingDismantle"];
const REPEATABLE=new Set(["project2","project40b","project51","project219","project133","project135"]);
// project200/201/217 end the company (the reference resets and reloads, which its
// host cannot trace); tests/test_sim.lua and tests/test_host.lua cover their
// effects and the host's restart (#23).
const STOPS=new Set(["project200","project201","project217"]);
test("every purchasable project is bought in a trace, with eligibility compared",()=>{
    const projected=run("projectsProduction").port.projection.state.filter(k=>/^project\d/.test(k));
    const bought=new Set();
    for (const name of PROJECT_RUNS) for (const state of states(run(name).port))
        for (const key of projected) if (state[key] && state[key].flag===1) bought.add(key);
    const missing=projected.filter(key=>!STOPS.has(key) && !bought.has(key));
    assert.deepEqual(missing,[]);
    assert.equal(bought.size,93);
    assert.ok(run("projectsProduction").port.projection.disabled.includes("projectButton1"),"project buttons compared");
});
test("one-use projects never return after purchase (no duplicate reward)",()=>{
    for (const name of PROJECT_RUNS) {
        const seenBought=new Set();
        for (const state of states(run(name).port)) {
            for (const project of state.activeProjects) {
                const key="project"+project.id.slice("projectButton".length);
                assert.ok(REPEATABLE.has(key) || !seenBought.has(key),name+": "+key+" returned after purchase");
            }
            for (const key of Object.keys(state)) if (/^project\d/.test(key) && state[key].flag===1) seenBought.add(key);
        }
    }
});
test("project effects: boosts, wire extrusion text, marketing, strategies and the picker",()=>{
    const production=final(run("projectsProduction").port).state;
    assert.deepEqual([production.clipperBoost,production.boostLvl,production.wireSupply,production.revPerSecFlag],
        [2.5,3,173250,1]);
    const messages=points(run("projectsProduction").port).map(p=>p.dom.readout1.html);
    assert.ok(messages.includes("Wire extrusion technique improved, 1,500 supply from every spool"));
    assert.ok(messages.includes("Using quantum foam annealment we now get 173,250 supply from every spool"));
    const creative=final(run("projectsCreativity").port).state;
    assert.equal(creative.marketingEffectiveness,3);
    assert.equal(creative.creativityOn,true);
    assert.equal(creative.strategyEngineFlag,1);
    const strategy=run("projectsStrategy").port, strategyEnd=final(strategy);
    assert.equal(strategyEnd.state.strats.length,8);
    assert.equal(strategyEnd.state.tourneyCost,16000,"Theory of Mind fixes the tournament cost");
    assert.equal(strategyEnd.state.yomiBoost,2);
    assert.equal(strategyEnd.dom.stratPicker.value,"7","the picker gained the strategy options");
    assert.equal(command(strategy,10,"stratPicker").dom.stratPicker.value,"");
    assert.equal(command(strategy,60,"projectButton60").dom.stratPicker.value,"10","option insertion selects the first");
    assert.equal(strategyEnd.state.project118.flag,0,"AutoTourney was shown but unaffordable");
    assert.equal(strategyEnd.dom.projectButton118.disabled,true);
});
test("repeatable projects: emergency wire, goodwill gifts, photonic chips and Xavier",()=>{
    const recovery=run("projectsRecovery").port, rec=final(recovery).state;
    assert.equal(rec.project2.flag,1);
    assert.equal(rec.trust,7,"two emergency spools cost 2 trust");
    assert.deepEqual([rec.memory,rec.processors,rec.creativitySpeed,rec.project219.uses],[0,0,0,1]);
    const business=final(run("projectsBusiness").port).state;
    assert.equal(business.bribe,8000000,"three gifts double the bribe three times");
    assert.deepEqual([business.investmentEngineFlag,business.demandBoost],[1,50]);
    const machines=final(run("projectsMachines").port).state;
    assert.deepEqual(machines.qChips.map(c=>c.active),[1,1,1,0,0,0,0,0,0,0]);
    assert.deepEqual([machines.qChipCost,machines.nextQchip,machines.qFlag,machines.megaClipperBoost,machines.wireBuyerFlag],
        [25000,3,1,2.75,1]);
    const volition=final(run("projectsVolition").port).state;
    assert.equal(volition.stockGainThreshold,0.54);
    const late=final(run("projectsLate").port).state;
    assert.deepEqual([late.project218.flag,late.autoTourneyFlag],[1,1]);
});
test("Release the HypnoDrones ends phase one at the reference transition and the planetary phase starts",()=>{
    const {port}=run("transition"), end=final(port);
    assert.deepEqual([end.state.humanFlag,end.state.trust,end.state.clipmakerLevel,end.state.megaClipperLevel],[0,0,0,0]);
    // No buildings yet: supply 0 >= demand 0 counts as fully powered (powMod 1); the
    // swarm sleeps until Swarm Computing.
    assert.deepEqual([end.state.powMod,end.state.swarmStatus,end.state.investmentEngineFlag,end.state.wireBuyerFlag],[1,6,0,0]);
    assert.equal(end.state.nanoWire,end.state.wire);
    assert.ok(!end.state.activeProjects.some(p=>p.id==="projectButton219"),"the shown Xavier button is removed");
    assert.ok(end.timers.some(t=>t.delay===32),"the hypnodrone blink runs");
    assert.deepEqual([end.dom.readout1.html,end.dom.readout2.html],["All of the resources of Earth are now available for clip production ",
        "Releasing the HypnoDrones "]);
});
// Planetary phase (#11, #12).
test("the phase-two project chain unlocks Toth tubules, power, wire production, drones and factories",()=>{
    const end=final(run("planetChain").port).state;
    assert.deepEqual([end.tothFlag,end.project127.flag,end.wireProductionFlag,end.harvesterFlag,end.wireDroneFlag,
        end.factoryFlag],[1,1,1,1,1,1]);
});
test("planetary buildings buy at exactly their cost; unaffordable clicks are no-ops, then controls disable",()=>{
    const {port}=run("planetExactCost");
    const levels=s=>[s.unusedClips,s.harvesterLevel,s.wireDroneLevel,s.factoryLevel,s.farmLevel,s.batteryLevel];
    assert.deepEqual(levels(command(port,0,"btnMakeHarvester").state),[112000000,1,0,0,0,0]);
    assert.deepEqual(levels(command(port,0,"btnMakeFactory").state),[11000000,1,1,1,0,0]);
    assert.deepEqual(levels(command(port,0,"btnMakeBattery").state),[0,1,1,1,1,1]);
    const noop=command(port,0,"btnMakeHarvester",1).state;
    assert.deepEqual(levels(noop),[0,1,1,1,1,1]);
    assert.equal(noop.harvesterCost,Math.pow(2,2.25)*1000000);
    const bulk=command(port,0,"btnFarmx10").state;
    assert.deepEqual([bulk.farmLevel,bulk.x],[1,100],"+10 recomputes the price sums (x ends at 100)");
    for (const id of ["btnMakeHarvester","btnMakeFactory","btnBatteryx10"]) {
        const point=command(port,30,id);
        assert.equal(point.dom[id].disabled,true,id);
        assert.deepEqual(levels(point.state),[0,1,1,1,1,1],id);
    }
});
test("a bulk purchase buys one at a time while affordable",()=>{
    const {port}=run("planetPartialBulk");
    const harvesters=command(port,0,"btnHarvesterx10").state;
    assert.equal(harvesters.harvesterLevel,3);
    assert.equal(harvesters.harvesterBill,1000000+Math.pow(2,2.25)*1000000+Math.pow(3,2.25)*1000000);
    assert.equal(command(port,0,"btnWireDronex100").state.wireDroneLevel,1);
});
test("power shortage, storage, bulk farms and momentum drive the matter-to-clips pipeline",()=>{
    const {port}=run("planetPipeline"), states=points(port).map(p=>p.state), end=states.at(-1);
    // The reference quirk: when storage runs out mid-shortage, nuSupply (2*supply - demand +
    // storedPower) can be negative, and so can powMod for that tick.
    assert.ok(states.some(s=>s.powMod<0),"a negative powMod tick");
    assert.ok(states.some(s=>s.powMod>0 && s.powMod<1),"a supply/demand fraction");
    assert.deepEqual([end.farmLevel,end.batteryLevel,end.harvesterLevel,end.wireDroneLevel,end.factoryLevel,end.momentum],
        [111,102,110,1010,4,1]);
    assert.ok(end.powMod>1,"momentum accelerates past full power");
    assert.ok(end.storedPower>0 && end.clips>0 && end.wire>0);
});
test("exhausted matter stops harvesting, empties wire and leaves the swarm bored and disorganized",()=>{
    const end=final(run("planetExhaustion").port);
    assert.deepEqual([end.state.availableMatter,end.state.wire,end.state.boredomFlag,end.state.disorgFlag,end.state.swarmStatus],
        [0,0,1,1,5]);
    assert.ok(end.state.activeProjects.some(p=>p.id==="projectButton46"),"Space Exploration appears");
    assert.deepEqual([end.dom.readout1.html,end.dom.readout2.html],[
        "No matter to harvest. Inactivity has caused the Swarm to become bored",
        "Imbalance between Harvester and Wire Drone levels has disorganized the Swarm"]);
});
test("Disassemble All refunds every bill and resets levels, costs and storage",()=>{
    const end=final(run("planetReboots").port).state;
    assert.deepEqual([end.harvesterLevel,end.wireDroneLevel,end.factoryLevel,end.farmLevel,end.batteryLevel,end.storedPower],
        [0,0,0,0,0,0]);
    assert.deepEqual([end.harvesterBill,end.wireDroneBill,end.factoryBill,end.farmBill,end.batteryBill],[0,0,0,0,0]);
    assert.deepEqual([end.harvesterCost,end.wireDroneCost,end.factoryCost,end.farmCost,end.batteryCost],
        [1000000,1000000,100000000,10000000,1000000]);
});
test("factory and drone upgrade projects multiply rates and boosts",()=>{
    const end=final(run("planetUpgrades").port).state;
    assert.deepEqual([end.factoryRate,end.factoryBoost,end.harvesterRate,end.wireDroneRate,end.droneBoost,end.yomi,end.unusedClips],
        [1e9*100*1000,1000,26180337*100*1000,16180339*100*1000,2,10000,1e21]);
    assert.ok(end.activeProjects.some(p=>p.id==="projectButton126"),"Swarm Computing appears (bought in swarmGifts)");
});
// The swarm (#13).
test("Swarm Computing reads the slider, the Active swarm earns gifts, and gifts buy capacity",()=>{
    const {port}=run("swarmGifts"), all=points(port);
    const bought=command(port,20,"projectButton126").state;
    assert.deepEqual([bought.swarmFlag,bought.yomi],[1,4000]);
    const gift=all.find(p=>p.state.swarmGifts>0).state;
    assert.deepEqual([gift.nextGift,gift.swarmGifts,gift.sliderPos],[4,4,"150"]);
    assert.ok(all.some(p=>p.state.swarmStatus===0),"the swarm is Active");
    const proc=command(port,400,"btnAddProc").state, mem=command(port,400,"btnAddMem").state;
    assert.deepEqual([proc.processors,mem.memory,mem.swarmGifts],[2,201,2]);
    const end=final(port).state;
    assert.equal(end.sliderPos,"0");
    assert.equal(end.giftCountdown.$number,"Infinity","a slider at 0 makes the countdown Infinity");
});
test("a spent gift countdown repeats the gift every tick while the swarm is not Active",()=>{
    const end=final(run("swarmRepeatGifts").port);
    assert.equal(end.state.swarmStatus,6);
    assert.ok(end.state.swarmGifts>=40,"a gift per tick");
    assert.equal(end.dom.readout1.html,"The swarm has generated a gift of 5 additional computational capacity");
});
test("the slider sanitizes like the page's range input and keeps a string",()=>{
    const {port}=run("swarmSlider");
    assert.deepEqual(points(port).filter(p=>p.kind==="command").map(p=>p.dom.slider.value),
        ["100","100","100","99","200","0","125","100"]);
    assert.equal(final(port).state.sliderPos,"100");
});
test("Entertain and Synchronize recover the swarm without checking their costs",()=>{
    const {port}=run("swarmRecovery");
    const once=command(port,20,"btnEntertainSwarm").state, twice=command(port,20,"btnEntertainSwarm",1).state;
    assert.deepEqual([once.creativity,once.entertainCost,once.boredomFlag],[15000,20000,0]);
    assert.deepEqual([twice.creativity,twice.entertainCost],[-5000,30000]);
    assert.deepEqual([command(port,20,"btnSynchSwarm",1).state.yomi,command(port,20,"btnSynchSwarm",1).state.disorgFlag],[-4000,0]);
    for (const id of ["btnEntertainSwarm","btnSynchSwarm"]) assert.equal(command(port,50,id).dom[id].disabled,true,id);
});
test("Space Exploration dismantles the planet with refunds and opens the cosmic phase",()=>{
    const {port}=run("spaceGate"), bought=command(port,30,"projectButton46").state;
    const end=final(port);
    assert.deepEqual([end.state.milestoneFlag,end.dom.readout1.html],[14,"Terrestrial resources fully utilized in "]);
    assert.deepEqual([bought.spaceFlag,bought.farmLevel,bought.powMod,bought.storedPower,bought.harvesterLevel,
        bought.batteryLevel,bought.harvesterBill,bought.batteryBill],[1,1,1,0,0,0,0,0]);
    assert.equal(command(port,30,"projectButton46").dom.readout1.html,"Von Neumann Probes online");
});
// The cosmic phase (#14).
test("probe design: trust at the pinned 1.47 power, allocations, maximum trust and launches",()=>{
    const {port}=run("probeDesign");
    const costs=points(port).filter(p=>p.kind==="command" && p.id==="btnIncreaseProbeTrust").map(p=>p.state.probeTrustCost);
    assert.deepEqual(costs,[1385,2513,3837,5326,6963,6963,6963,6963],"Yomi runs out after five");
    const raised=command(port,20,"btnRaiseProbeRep",1).state;
    assert.deepEqual([raised.probeRep,raised.probeTrust],[2,5],"a raise past the trust before the next tick still counts unused trust");
    const end=final(port).state;
    assert.deepEqual([end.maxTrust,end.probeLaunchLevel,end.probeSpeed,end.probeCombat],[30,2,2,1]);
    assert.ok(Math.abs(end.attackSpeed-0.4)<1e-12,"two speed raises move attackSpeed");
    assert.ok(end.foundMatter>6e27 && end.factoryLevel>0 && end.drifterCount>0);
});
test("a probe population replicates, meets hazards, builds and drifts with large numbers",()=>{
    const end=final(run("probeGrowth").port).state;
    assert.ok(end.probeDescendents>0 && end.probesLostHaz>1e6 && end.drifterCount>0 && end.drifterCount<1e6);
    assert.ok(end.factoryLevel>0 && end.harvesterLevel===end.wireDroneLevel && end.clips>0);
    assert.equal(end.foundMatter,Math.pow(10,54)*30,"the survey is clamped at the universe's matter");
    const survey=final(run("probeSurvey").port).state;
    assert.ok(survey.foundMatter>6e27 && survey.availableMatter>3e26);
});
test("clips limit replication and probe launches",()=>{
    const {port}=run("probeShortage"), launch=points(port).find(p=>p.kind==="command").state;
    assert.equal(launch.probeLaunchLevel,0,"too few clips for a launch");
    assert.ok(launch.unusedClips<launch.probeCost);
});
test("the cosmic phase projects: Strategic Attachment, Elliptic Hull Polytopes, Reboot the Swarm",()=>{
    const end=final(run("spaceProjects").port);
    assert.deepEqual([end.state.project128.flag,end.state.project129.flag,end.state.project130.flag],[1,1,1]);
    assert.equal(end.dom.readout1.html,"Swarm computing back online");
});
test("with every probe lost and too few clips, Memory release appears",()=>{
    const end=final(run("spaceRecovery").port);
    assert.ok(end.state.activeProjects.some(p=>p.id==="projectButton135"));
    assert.equal(end.dom.projectButton135.disabled,false,"200 memory pays its 10");
});
// Battles (#15).
test("drifters past warTrigger start a battle whose ship losses cost probes and drifters",()=>{
    const all=points(run("spaceWar").port).map(p=>p.state), end=all.at(-1);
    assert.deepEqual([end.battleFlag,end.battleID,end.battleName],[1,1,"Drifter Attack 1"]);
    assert.ok(end.probesLostCombat>0 && end.driftersKilled>0,"each destroyed ship costs unitSize");
    assert.ok(all.some(s=>s.unitSize>1),"a ship stands for many probes or drifters");
});
test("named battles won: honor from the drifter fleet, names, the result delay and the OODA Loop",()=>{
    const all=points(run("battleVictory").port).map(p=>p.state), end=all.at(-1);
    assert.deepEqual([end.project121.flag,end.project131.flag,end.project120.flag,end.attackSpeedFlag,end.battleEndTimer],
        [1,1,1,1,200]);
    const names=new Set(all.map(s=>s.battleName));
    assert.ok(["Fuentes de Onoro 1","Borodino 1"].every(n=>names.has(n)),[...names].join("|"));
    assert.ok(end.honor>0,"victory honor");
    assert.ok(all.some((s,i)=>i>0 && s.battles.length<all[i-1].battles.length),"a battle ends");
});
test("named battles lost: honor falls by the probe fleet and the threnody takes the battle's name",()=>{
    const all=points(run("battleDefeat").port).map(p=>p.state);
    // The checkpoint where a defeat lowers honor: the threnody takes that battle's name.
    const defeat=all.find((s,i)=>i>0 && s.honor<all[i-1].honor);
    assert.ok(defeat,"a defeat costs honor");
    assert.equal(defeat.threnodyTitle,defeat.battleName);
    assert.notEqual(defeat.threnodyTitle,"Durenstein 1");
    assert.ok(all.at(-1).honor<0);
});
test("undecided battles end after 8,000 updates, or 2,000 with four ships or fewer on a side",()=>{
    for (const name of ["battleTimeout","battleClockTimeout"]) {
        const all=points(run(name).port).map(p=>p.state);
        assert.equal(all[1].battles.length,1,name+" starts with a battle");
        const end=all.at(-1);
        assert.deepEqual([end.battles.length,end.battleClock,end.honorCount],[0,0,0],name);
    }
});
test("the WireBuyer switch stops and resumes automatic wire purchases",()=>{
    const {port}=run("wireBuyerToggle");
    const off=command(port,0,"btnToggleWireBuyer").state;
    assert.deepEqual([off.wireBuyerStatus,off.wirePurchase],[0,0]);
    const before=command(port,300,"btnToggleWireBuyer").state;
    assert.deepEqual([before.wireBuyerStatus,before.wirePurchase,before.wire],[1,0,0.5],"nothing bought while off");
    const end=final(port).state;
    assert.ok(end.wirePurchase>=1 && end.wire>1,"WireBuyer resumes");
});
// The correspondence, memorials and recovery (#16).
test("milestone 15 opens the Emperor of Drift's seven messages, then Accept and Reject",()=>{
    const end=final(run("correspondence").port);
    assert.equal(end.state.milestoneFlag,15);
    for (let n=140;n<=146;n++) assert.equal(end.state["project"+n].flag,1,"project"+n);
    assert.deepEqual(end.state.activeProjects.map(p=>p.id).filter(id=>/14[78]$/.test(id)),
        ["projectButton147","projectButton148"]);
    assert.equal(end.dom.readout1.html,"Universal Paperclips achieved in ");
    assert.equal(final(run("surveyedEnd").port).state.milestoneFlag,15,"the surveyed, used-up universe");
});
test("memorials: the monument, the repeatable threnody at rising cost, and Glory",()=>{
    const end=final(run("memorials").port).state;
    assert.deepEqual([end.project132.flag,end.project133.flag,end.project134.flag],[1,1,1]);
    assert.deepEqual([end.honor,end.threnodyCost],[50000+10000+10000,70000]);
    assert.ok(end.activeProjects.some(p=>p.id==="projectButton133"),"the threnody returns");
});
test("Memory release trades 10 memory for 10^22 clips and stays repeatable",()=>{
    const end=final(run("memoryRelease").port);
    assert.deepEqual([end.state.memory,end.state.unusedClips,end.state.project135.uses],[20,1e16+1e22,1]);
    assert.equal(end.dom.readout1.html,"release the \u00f8\u00f8\u00f8\u00f8\u00f8 release ");
});
// The endings (#17).
test("Reject: the end timer unlocks the probes' dismantling, then the swarm's",()=>{
    const end=final(run("endingReject").port);
    assert.deepEqual([end.state.project148.flag,end.state.project210.flag,end.state.project211.flag,end.state.dismantle],
        [1,1,1,2]);
    assert.deepEqual([end.state.probeCount,end.state.harvesterLevel,end.state.wireDroneLevel],[0,0,0]);
    assert.ok(!end.state.activeProjects.some(p=>/14[78]$/.test(p.id)),"either choice removes both buttons");
    assert.deepEqual([end.dom.readout1.html,end.dom.readout2.html],["Dismantling the swarm","Dismantling probe facilities"]);
});
test("Accept offers the two new universes",()=>{
    const end=final(run("endingAccept").port).state;
    assert.equal(end.project147.flag,1);
    assert.deepEqual(end.activeProjects.map(p=>p.id).filter(id=>/20[01]$/.test(id)),["projectButton200","projectButton201"]);
});
test("the dismantling ends in final clips made by hand and the credits",()=>{
    const end=final(run("endingDismantle").port);
    assert.deepEqual([end.state.dismantle,end.state.processors,end.state.memory,end.state.creativityOn,end.state.autoTourneyFlag],
        [7,0,0,false,0]);
    assert.deepEqual([end.state.finalClips,end.state.wire,end.state.milestoneFlag],[100,0,20]);
    assert.ok(end.state.qChips.every(c=>c.value===0.5),"the photonic chips rest");
    assert.equal(end.dom.readout1.html,"\u00a9 2017 Everybody House Games");
});
test("the project traceability checklist is current",()=>{
    const Checklist=require("./project_checklist.cjs");
    const purchases={};
    for (const name of Workshop.names) purchases[name]=run(name).port.purchases;
    assert.equal(require("node:fs").readFileSync(Checklist.OUTPUT,"utf8"),Checklist.generate(purchases));
    // Every project is bought in a trace or is a restart covered by the Lua tests.
    const bought=new Set(Object.values(purchases).flat());
    for (const name of Object.keys(Checklist.RESTARTS)) assert.ok(!bought.has(name),name+" is a restart");
    assert.equal(bought.size+Object.keys(Checklist.RESTARTS).length,96);
});

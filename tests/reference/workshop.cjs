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
function stream(length=60000, offset=0) {
    return Array.from({length},(_,i)=>((i+offset)*0.6180339887498949)%1);
}
const click=(at,id)=>({at,type:"click",id});
// qChip0..qChip9 with the first `active` chips switched on (project effects, #8).
const value=(at,id,v)=>({at,type:"value",id,value:v});
// Operations to afford tournaments: Operations run and refill toward memory.
// A purchase chain: each project button is clicked 20 ms after the previous one,
// which leaves a tick for the next project to appear and its button to update.
const buy=(from,...names)=>names.map((n,i)=>click(from+i*20,"projectButton"+n));
// Plenty of Operations for project costs (memory caps standardOps).
const rich=(memory,extra={})=>({compFlag:1,projectsFlag:1,memory,standardOps:memory*1000,...extra});
const tourney=()=>({compFlag:1,strategyEngineFlag:1,memory:20,standardOps:15000});
// The planetary phase (after Release the HypnoDrones) with Operations for projects.
const planet=(extra={})=>rich(200,{humanFlag:0,trust:0,...extra});
// The cosmic phase (after Space Exploration): the planet dismantled, one farm.
const space=(extra={})=>planet({spaceFlag:1,availableMatter:0,farmLevel:1,powMod:1,milestoneFlag:14,...extra});
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
    // Investments (#7). A deposit funds stockShop purchases (generated symbols,
    // priced by roll), price updates every 2.5 s and a sale once sellDelay reaches 5.
    // streamOffset shifts the recorded stream so the 25 % purchase rolls succeed.
    investments:{until:6000,streamLength:90000,streamOffset:6000,
        fixture:{globals:{funds:20000,investmentEngineFlag:1,sellDelay:4}},
        commands:[click(0,"btnInvest"),value(100,"investStrat","med"),click(3000,"btnInvest")]},
    investmentSale:{until:6000,streamLength:90000,streamOffset:5000,
        fixture:{globals:{funds:20000,investmentEngineFlag:1,sellDelay:4}},commands:[click(0,"btnInvest")]},
    // High risk: the whole bankroll is the budget; an unknown risk value empties the
    // select, which the reference also treats as high risk; then a withdrawal.
    investmentRisk:{until:4200,streamLength:70000,streamOffset:1000,fixture:{globals:{funds:5000,investmentEngineFlag:1}},
        commands:[value(0,"investStrat","hi"),click(0,"btnInvest"),value(2100,"investStrat","bogus"),
            click(4100,"btnWithdraw")]},
    // Engine upgrades spend Yomi without a check of their own: a second click before
    // the next tick drives Yomi negative; then the control disables.
    investUpgrade:{until:300,fixture:{globals:{yomi:500,investmentEngineFlag:1}},commands:[
        click(0,"btnImproveInvestments"),click(0,"btnImproveInvestments"),click(50,"btnImproveInvestments")]},
    // The lifetime report formats ledger + portfolio with formatWithCommas.
    investReport:{until:300,fixture:{globals:{investmentEngineFlag:1,stockReportCounter:9990,bankroll:123456789,
        ledger:-2500.75}},commands:[]},
    // Tournaments (#7): two-strategy pools cover every pickMove; strategy 0 is picked.
    tourneyGreedy:{until:4600,streamLength:60000,fixture:{globals:tourney(),strategies:[3,4]},
        commands:[value(0,"stratPicker","0"),click(20,"btnNewTournament"),click(30,"btnRunTournament"),
            click(40,"btnRunTournament")]},
    tourneyMinimax:{until:4600,streamLength:60000,fixture:{globals:tourney(),strategies:[5,6]},
        commands:[value(0,"stratPicker","0"),click(20,"btnNewTournament"),click(30,"btnRunTournament")]},
    tourneyBeatLast:{until:4600,streamLength:60000,fixture:{globals:tourney(),strategies:[7,0]},
        commands:[value(0,"stratPicker","0"),click(20,"btnNewTournament"),click(30,"btnRunTournament")]},
    tourneyFixed:{until:4600,streamLength:60000,fixture:{globals:tourney(),strategies:[1,2]},
        commands:[value(0,"stratPicker","0"),click(20,"btnNewTournament"),click(30,"btnRunTournament")]},
    // Automatic tournaments: after a finished tournament with results shown, 300
    // ticks start the next one; without a picked strategy no Yomi or results flag.
    autoTourney:{until:5600,streamLength:80000,fixture:{globals:{...tourney(),autoTourneyFlag:1}},
        commands:[value(0,"stratPicker","0"),click(20,"btnNewTournament"),click(30,"btnRunTournament")]},
    noPick:{until:1500,fixture:{globals:tourney()},
        commands:[click(20,"btnNewTournament"),click(30,"btnRunTournament")]},
    // Projects (#8). AutoClipper and wire-extrusion chains, with toLocaleString text.
    projectsProduction:{until:600,fixture:{globals:rich(60,{clipmakerLevel:1,wirePurchase:1,wireCost:130})},
        commands:[...buy(20,"1","4","5"),...buy(100,"7","8","9","10","10b","42")]},
    // Creativity projects, their marketing and AutoClipper follow-ups, then the
    // strategy engine.
    projectsCreativity:{until:700,fixture:{globals:rich(40,{creativityOn:1,creativity:900,trust:5})},
        commands:[...buy(20,"3","6","13","14","15","17"),...buy(160,"19","11","12","16","20")]},
    // The strategy engine and all seven strategy purchases; the picker gains options.
    // AutoTourney then shows but is unaffordable, so its click is ignored.
    projectsStrategy:{until:500,fixture:{globals:rich(200,{creativity:60000,trust:95})},
        // An unmatched picker value empties the select; the first strategy option
        // added then selects "Pick a Strat" (native_select_probe).
        commands:[value(10,"stratPicker","3"),...buy(20,"19","20","60","61","62","63","64","65","66","119","118"),
            value(260,"stratPicker","7")]},
    // Investment unlock, takeover, monopoly and the repeating goodwill gifts.
    projectsBusiness:{until:600,fixture:{globals:rich(20,{trust:89,bankroll:20000,funds:30000000,yomi:5000,
        clips:101000000,nextTrust:1e12})},commands:[...buy(150,"21","37","38","40","40b"),click(260,"projectButton40b"),
            click(300,"projectButton40b")]},
    // Coherent extrapolated volition and its four follow-ups.
    projectsVolition:{until:400,fixture:{globals:rich(200,{yomi:30000,creativity:600})},
        commands:[...buy(20,"27","28","29","30","31")]},
    // MegaClippers, their boosts, WireBuyer, quantum computing and three photonic chips.
    projectsMachines:{until:800,fixture:{globals:rich(150,{clipmakerLevel:75,wirePurchase:15,processors:5,
        wire:3})},commands:[...buy(20,"22","23","24","25","26","50","51"),click(180,"projectButton51"),
            click(200,"projectButton51")]},
    // Emergency wire (a two-inch spool at a one-cent price sells out quickly, so the
    // repeatable project returns) and Xavier re-initialization.
    projectsRecovery:{until:1500,fixture:{globals:rich(5,{wire:0.5,funds:0,unsoldClips:0,trust:9,wireSupply:2,
        margin:.01,creativityOn:1,creativity:100000,processors:3,memory:4,standardOps:4000})},
        commands:[click(20,"projectButton2"),click(30,"btnMakePaperclip"),click(40,"btnMakePaperclip"),
            click(50,"projectButton219"),click(120,"projectButton2")]},
    // The WireBuyer switch: off, the empty spool stays empty; on again, WireBuyer buys
    // at the next tick.
    wireBuyerToggle:{until:600,fixture:{globals:{wireBuyerFlag:1,wire:0.5,funds:500}},commands:[
        click(0,"btnToggleWireBuyer"),click(300,"btnToggleWireBuyer")]},
    // Late phase-one creativity purchases: Limerick (cont.) and AutoTourney.
    projectsLate:{until:300,fixture:{globals:rich(10,{strategyEngineFlag:1,trust:95,creativity:1100000})},
        commands:[...buy(20,"218","118")]},
    // The first transition: Hypno Harmonics, HypnoDrones and Release the HypnoDrones,
    // which removes the shown Xavier button; the next tick reaches phase two (#11).
    transition:{until:400,fixture:{globals:rich(120,{creativity:100500,trust:101})},
        commands:[...buy(20,"13","14","12","34","70","35")]},
    // Planetary phase (#11, #12). The phase-two project chain: Toth Tubule Enfolding,
    // Power Grid, Nanoscale Wire Production, both drone types and Clip Factories.
    // Many processors refill Operations between purchases.
    planetChain:{until:600,fixture:{globals:planet({creativity:300,processors:200000})},
        commands:[...buy(20,"17","18","127","41","43","44"),click(160,"projectButton45")]},
    // Exact-cost builds of all five buildings (113 million clips: two drones at
    // 1e6, a factory at 1e8, a farm at 1e7, a battery at 1e6) leave exactly 0;
    // then unaffordable clicks: before the next tick they run each function's own
    // no-op branch (+10 still recomputes the price sums), afterwards the disabled
    // controls ignore them. No wire or matter, so nothing produces clips meanwhile.
    planetExactCost:{until:300,fixture:{globals:planet({unusedClips:113000000,wire:0,availableMatter:0})},commands:[
        click(0,"btnMakeHarvester"),click(0,"btnMakeWireDrone"),click(0,"btnMakeFactory"),click(0,"btnMakeFarm"),
        click(0,"btnMakeBattery"),click(0,"btnMakeHarvester"),click(0,"btnMakeFarm"),click(0,"btnFarmx10"),
        click(30,"btnMakeHarvester"),click(30,"btnMakeFactory"),click(30,"btnBatteryx10")]},
    // A bulk purchase buys one at a time while affordable: +10 harvesters with 20
    // million clips buys three (1e6, then the 2.25-power costs) and stops; before
    // any purchase the price sums are 0, so the multi-buy buttons start enabled.
    planetPartialBulk:{until:200,fixture:{globals:planet({unusedClips:20000000})},commands:[
        click(0,"btnHarvesterx10"),click(0,"btnWireDronex100"),click(50,"btnWireDronex10")]},
    // Throughput under power: a shortage with stored power drains the batteries,
    // then powMod is supply/demand; bulk farm purchases restore full power with
    // surplus into storage; Momentum then accelerates powMod while fully powered.
    // Harvesters, wire drones and factories run the whole matter-to-clips chain.
    planetPipeline:{until:1500,fixture:{globals:planet({harvesterLevel:10,wireDroneLevel:10,factoryLevel:2,
        farmLevel:1,batteryLevel:2,storedPower:3,unusedClips:5e15,creativity:30000,processors:200000})},
        commands:[click(300,"btnFarmx10"),click(600,"btnFarmx100"),click(620,"projectButton125"),
            click(700,"btnHarvesterx100"),click(700,"btnWireDronex1000"),click(710,"btnMakeFactory"),
            click(710,"btnMakeFactory"),click(900,"btnBatteryx100")]},
    // Exhausted material: the last available matter is harvested (Space Exploration
    // appears), acquired matter becomes wire, factories use up the wire; boredom
    // reaches its threshold and the imbalanced swarm becomes disorganized.
    planetExhaustion:{until:1200,fixture:{globals:planet({harvesterLevel:60,wireDroneLevel:5,factoryLevel:1,
        farmLevel:50,availableMatter:3e10,boredomLevel:29960,disorgCounter:99.99})},commands:[]},
    // Every Disassemble All: refunds of the bills, recomputed price sums, the reset
    // costs (farms 1e7, batteries 1e6) and the emptied battery storage.
    planetReboots:{until:500,fixture:{globals:planet({unusedClips:5e13,farmLevel:3,storedPower:500})},commands:[
        click(0,"btnHarvesterx10"),click(0,"btnMakeHarvester"),click(0,"btnWireDronex10"),click(0,"btnMakeFactory"),
        click(0,"btnMakeFactory"),click(0,"btnFarmx10"),click(0,"btnBatteryx10"),
        click(100,"btnHarvesterReboot"),click(100,"btnWireDroneReboot"),click(100,"btnFactoryReboot"),
        click(200,"btnFarmReboot"),click(200,"btnBatteryReboot"),click(300,"btnHarvesterReboot")]},
    // The factory and drone upgrade projects, including 10^21 clips for the
    // self-correcting supply chain; Swarm Computing appears but is not bought (#13).
    planetUpgrades:{until:500,fixture:{globals:planet({factoryLevel:50,harvesterLevel:25000,wireDroneLevel:25000,
        yomi:60000,unusedClips:2e21,processors:300000})},
        commands:[...buy(20,"100","101","102","110","111","112")]},
    // The swarm (#13). Swarm Computing makes the swarm Active and reads the slider;
    // moving it toward "think" raises the gift rate (log of the swarm size times
    // sliderPos/100). Near the gift period a gift arrives (round(log10(300) * 1.5) = 4),
    // giftBits restarts, and gifts buy processors and memory.
    swarmGifts:{until:1200,fixture:{globals:planet({harvesterLevel:150,wireDroneLevel:150,farmLevel:10,yomi:40000,
        giftBits:124950})},commands:[click(20,"projectButton126"),value(30,"slider","150"),
            click(400,"btnAddProc"),click(400,"btnAddMem"),value(600,"slider","0")]},
    // After a gift, giftCountdown is only recomputed while the swarm is Active. A
    // sleeping swarm (no power) with a spent countdown gives a gift every tick.
    swarmRepeatGifts:{until:200,fixture:{globals:planet({harvesterLevel:150,wireDroneLevel:150,swarmFlag:1,
        giftCountdown:0})},commands:[value(50,"slider","200")]},
    // Slider values sanitized as the page's range input: invalid syntax takes the
    // midpoint, values clamp and round with ties upward; sliderPos holds the string,
    // and the work multiplier (200 - sliderPos)/100 scales harvesting and wire.
    swarmSlider:{until:900,fixture:{globals:planet({harvesterLevel:20,wireDroneLevel:20,farmLevel:5,swarmFlag:1})},
        commands:["99.5","","0x10","99.49","201","-1","1.25e2","42 "].map((v,i)=>value(50+i*100,"slider",v))},
    // Recovery: Entertain and Synchronize reset boredom and disorganization. Neither
    // checks its cost, so a second click before the next tick overspends; then the
    // controls disable.
    swarmRecovery:{until:400,fixture:{globals:planet({harvesterLevel:30,wireDroneLevel:5,farmLevel:5,
        boredomFlag:1,disorgFlag:1,disorgCounter:100,creativity:25000,yomi:6000})},
        commands:[click(20,"btnEntertainSwarm"),click(20,"btnEntertainSwarm"),click(20,"btnSynchSwarm"),
            click(20,"btnSynchSwarm"),click(50,"btnEntertainSwarm"),click(50,"btnSynchSwarm")]},
    // The expansion gate: with the Earth's matter gone, Space Exploration appears; its
    // purchase dismantles every building with refunds and starts the cosmic phase,
    // where the next tick stops explicitly (#14).
    spaceGate:{until:300,fixture:{globals:planet({availableMatter:0,harvesterLevel:40,wireDroneLevel:40,
        factoryLevel:5,farmLevel:20,batteryLevel:2000,storedPower:15000000,unusedClips:6e27,processors:300000,
        harvesterBill:5e9,factoryBill:7e9,farmBill:3e9,batteryBill:2e9,milestoneFlag:13})},
        commands:[click(30,"projectButton46")]},
    // The cosmic phase (#14). Probe design: trust bought with Yomi at
    // floor(Math.pow(trust + 1, 1.47) * 500), every allocation raised and one
    // lowered, a raise past the trust before the next tick (the function's own check),
    // maximum trust from honor, and two probe launches; then the probes survey,
    // replicate, meet hazards, build and drift.
    probeDesign:{until:800,fixture:{globals:space({yomi:20000,honor:100000,unusedClips:1e30})},commands:[
        ...clicks(0,8,0,"btnIncreaseProbeTrust"),
        ...["Speed","Nav","Rep","Haz","Fac","Harv","Wire","Combat"].map(n=>click(20,"btnRaiseProbe"+n)),
        click(20,"btnRaiseProbeSpeed"),click(20,"btnLowerProbeCombat"),click(20,"btnRaiseProbeRep"),
        click(30,"btnIncreaseMaxTrust"),click(30,"btnMakeProbe"),click(30,"btnMakeProbe")]},
    // A large probe population: replication, whole-probe hazard losses, probe-built
    // factories and drones, and drift into drifters (below warTrigger). The universe
    // is already fully surveyed, so the survey is clamped to 0, while the remaining
    // available matter and wire keep the final milestone away.
    probeGrowth:{until:1000,fixture:{globals:space({probeCount:2e7,probeTrust:24,maxTrust:30,probeSpeed:3,
        probeNav:3,probeRep:5,probeHaz:3,probeFac:3,probeHarv:3,probeWire:3,unusedClips:1e40,
        foundMatter:Math.pow(10,54)*30,availableMatter:1e30})},commands:[]},
    // Surveying below the limit: xRate = floor(probes) * 1.75e18 * speed * nav.
    probeSurvey:{until:400,fixture:{globals:space({probeCount:1e6,probeSpeed:2,probeNav:3,probeTrust:5})},commands:[]},
    // Clips run out: replication and the probe-built factories and drones are
    // clamped to what the clips pay for; the probe launch then refuses.
    probeShortage:{until:600,fixture:{globals:space({probeCount:4e6,probeTrust:9,probeRep:3,probeFac:2,probeHarv:2,
        probeWire:2,unusedClips:3.5e17})},commands:[click(300,"btnMakeProbe")]},
    // The cosmic phase's projects: Strategic Attachment (eight strategies, the next
    // trust cost above Yomi), Elliptic Hull Polytopes halving hazard losses, and
    // Reboot the Swarm, which ends the swarm's NO RESPONSE status.
    spaceProjects:{until:700,fixture:{globals:space({creativity:200000,processors:300000,probesLostHaz:150,
        harvesterLevel:30,wireDroneLevel:30,probeCount:2e6,probeHaz:2,probeTrust:2}),strategies:[0,1,2,3,4,5,6,7]},
        commands:[...buy(20,"128","129","130")]},
    // Every probe lost without clips for a new one: Memory release appears (its
    // purchase is cosmic recovery, #16).
    spaceRecovery:{until:200,fixture:{globals:space({probeCount:0,unusedClips:1e16})},commands:[]},
    // Drifters pass warTrigger: the next battle roll is #15, where the slice stops.
    spaceWar:{until:400,fixture:{globals:space({probeCount:1e8,probeTrust:30,maxTrust:30,drifterCount:900000})},
        commands:[]},
};
function make(name) {
    if (!Object.hasOwn(traces,name)) throw new Error("Unknown workshop trace: "+name);
    const trace=JSON.parse(JSON.stringify(traces[name]));
    trace.random=stream(trace.streamLength,trace.streamOffset); delete trace.streamLength; delete trace.streamOffset;
    trace.drawing=true;
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

"use strict";
// Issue #4 acceptance: deliberate divergences are reported at the first differing
// draw, callback or field, with source hashes and surrounding trace evidence.
const test=require("node:test"), assert=require("node:assert/strict");
const fs=require("node:fs"), path=require("node:path"), os=require("node:os"), vm=require("node:vm");
const {spawnSync}=require("node:child_process");
const Harness=require("../../Tools/reference/host.js");
const Runner=require("../../Tools/reference/runner.cjs"), Traces=require("./traces.cjs");
const source=Runner.inputs();
const full=(trace,prepare)=>Runner.report(Runner.run(trace,source,prepare).result,source,true);
const inject=(runner,code)=>vm.runInContext(code,runner.context,{filename:"injected.js"});
const baseline=full(Traces.make("workshop"));

function assertEvidence(found) {
    assert.deepEqual(found.source_sha256.left,source.index.source_sha256);
    assert.deepEqual(found.source_sha256.right,source.index.source_sha256);
    assert.match(found.input.left.trace_sha256,/^[0-9a-f]{64}$/);
    assert.match(found.input.left.random_sha256,/^[0-9a-f]{64}$/);
    assert.ok(found.context.left.length>0 && found.context.right.length>0);
    assert.deepEqual(found.context.left,found.context.right,"evidence before the divergence agrees");
}

test("identical runners report no divergence",()=>{
    assert.equal(Runner.compare(baseline,full(Traces.make("workshop")),source),null);
});
test("a deliberate extra draw is reported at its ordinal and call site",()=>{
    // Wrap the inline-handler target of btnBuyWire; the extra draw happens at t=0.
    const right=full(Traces.make("workshop"),runner=>inject(runner,
        "var original=buyWire; buyWire=function(){ Math.random(); return original.apply(this,arguments); };"));
    const found=Runner.compare(baseline,right,source);
    assert.equal(found.kind,"draw");
    assert.equal(found.ordinal,3200,"after the 3,200 initialization draws");
    assert.equal(found.right.action,"draw");
    assert.match(found.right.site,/^injected\.js:1:\d+$/);
    assert.equal(found.right.scope,null);
    assert.deepEqual({action:found.left.action,type:baseline.checkpoints[found.left.index].type,
        id:baseline.checkpoints[found.left.index].id},{action:"checkpoint",type:"click",id:"btnBuyWire"});
    assert.deepEqual([found.after.kind,found.after.id],["command","btnMakePaperclip"]);
    assertEvidence(found);
});
test("a branch that skips a reference draw is reported at the skipped draw",()=>{
    // Ported code that skips adjustWirePrice takes a different branch inside the
    // 100 ms sales interval; its first missing draw identifies the site.
    const right=full(Traces.make("workshop"),runner=>inject(runner,"adjustWirePrice=function(){};"));
    const found=Runner.compare(baseline,right,source);
    assert.equal(found.kind,"draw");
    assert.equal(found.left.site,"main.js:704:14");
    assert.equal(found.left.scope,"adjustWirePrice@695");
    assert.equal(found.ordinal,found.left.ordinal);
    assert.equal(found.right.site,"main.js:4574:18","the next reference draw arrives one ordinal early");
    assert.equal(found.right.ordinal,found.left.ordinal);
    assert.equal(found.after.kind,"callback");
    assertEvidence(found);
});
test("a branch mismatch without draws is reported at the first differing state field",()=>{
    const right=full(Traces.make("workshop"),runner=>inject(runner,
        "var original=clipClick; clipClick=function(n){ return original.call(this,n+1); };"));
    const found=Runner.compare(baseline,right,source);
    assert.equal(found.kind,"state");
    assert.equal(baseline.checkpoints[found.checkpoint].id,"btnMakePaperclip");
    assert.equal(found.difference.path,"$.state.clips");
    assert.equal(found.difference.category,"resource");
    assert.deepEqual([found.difference.left,found.difference.right],[1,2]);
    assert.equal(found.difference.ulps,Harness.ulps(1,2));
    assertEvidence(found);
});
test("an altered callback order is reported at the first reordered callback",()=>{
    const trace=Traces.make("initialization"), left=full(trace);
    // Reverse the stable tie-break for equal due times.
    const right=full(trace,runner=>{
        runner.harness.clock.next=function(){
            return [...this.pending.values()].sort((a,b)=>a.due-b.due || b.order-a.order)[0];
        };
    });
    const found=Runner.compare(left,right,source);
    assert.equal(found.kind,"timer");
    assert.equal(found.field,"$.id");
    assert.equal(found.left.action,"fire");assert.equal(found.right.action,"fire");
    assert.equal(found.left.at,found.right.at);
    assert.notEqual(found.left.id,found.right.id);
    assertEvidence(found);
});
test("hash-only checkpoints locate a state divergence; mismatched sources stop comparison",()=>{
    const strip=doc=>({...doc,checkpoints:doc.checkpoints.map(({json,...meta})=>meta)});
    const changed=JSON.parse(JSON.stringify(baseline));
    const point=changed.checkpoints[5], state=JSON.parse(point.json);
    state.state.funds+=1; point.json=JSON.stringify(state); point.sha256=Runner.sha256(point.json);
    const found=Harness.compareTraces(strip(baseline),strip(changed));
    assert.deepEqual([found.kind,found.checkpoint,found.difference],["state",5,null]);
    assert.notEqual(found.sha256.left,found.sha256.right);
    assert.equal(Runner.compare(baseline,changed,source).difference.path,"$.state.funds");
    const other={...baseline,source_sha256:{...baseline.source_sha256,"main.js":"0".repeat(64)}};
    assert.equal(Harness.compareTraces(baseline,other).kind,"source");
    // Hash key order is not significant (a Lua runner may emit another order).
    const reordered={...baseline,source_sha256:Object.fromEntries(Object.entries(baseline.source_sha256).reverse())};
    assert.equal(Harness.compareTraces(baseline,reordered),null);
});
test("checkpoints are compared from either representation and malformed documents are refused",()=>{
    const hashOnly=({json,...meta})=>meta, jsonOnly=({sha256,...meta})=>meta;
    const mixed=(doc,form)=>({...doc,checkpoints:doc.checkpoints.map(form)});
    assert.equal(Harness.compareTraces(baseline,mixed(baseline,jsonOnly)),null,"identical JSON matches a hashed checkpoint");
    assert.equal(Harness.compareTraces(mixed(baseline,hashOnly),baseline),null);
    assert.throws(()=>Harness.compareTraces(mixed(baseline,hashOnly),mixed(baseline,jsonOnly)),/needs JSON or SHA-256 on both sides/);
    // Every checkpoint needs its event, so a differing checkpoint cannot hide.
    const noEvents={...baseline,events:baseline.events.filter(e=>e.action!=="checkpoint")};
    assert.throws(()=>Harness.compareTraces(baseline,noEvents),/73 checkpoints but 0 checkpoint events/);
    const extra={...baseline,checkpoints:[...baseline.checkpoints,baseline.checkpoints.at(-1)]};
    assert.throws(()=>Harness.compareTraces(baseline,extra),/74 checkpoints but 73/);
    const skipped={...baseline,events:baseline.events.map(e=>e.action==="checkpoint" && e.index===3 ? {...e,index:4} : e)};
    assert.throws(()=>Harness.compareTraces(skipped,baseline),/left checkpoint events must cover checkpoints in index order/);
    assert.throws(()=>Harness.compareTraces({...baseline,schema:1},baseline),/left trace schema 1 is not supported/);
    assert.throws(()=>Harness.compareTraces(baseline,{schema:2}),/right trace needs events and checkpoints/);
});
test("arrays never equal objects with the same keys in full comparisons",()=>{
    const doc=full(Traces.make("initialization"));
    const substitute=(value,replacement)=>{
        const changed=JSON.parse(JSON.stringify(doc)), point=changed.checkpoints[0], state=JSON.parse(point.json);
        state.state.activeProjects=value; point.json=JSON.stringify(state); point.sha256=Runner.sha256(point.json);
        const base=JSON.parse(JSON.stringify(doc)), basePoint=base.checkpoints[0], baseState=JSON.parse(basePoint.json);
        baseState.state.activeProjects=replacement; basePoint.json=JSON.stringify(baseState);
        basePoint.sha256=Runner.sha256(basePoint.json);
        return Runner.compare(base,changed,source);
    };
    for (const [array,object] of [[[],{}],[[1],{0:1}]]) {
        const found=substitute(object,array);
        assert.deepEqual([found.kind,found.checkpoint,found.difference.path],["state",0,"$.state.activeProjects"]);
        assert.equal(found.difference.category,"project");
    }
    assert.deepEqual(Harness.firstDifference([1,2],[1]),{path:"$.length",left:2,right:1});
    assert.equal(Harness.firstDifference([1,{a:[]}],[1,{a:[]}]),null);
    // A differing hash is never accepted, even when the JSON walk finds no field.
    const odd=JSON.parse(JSON.stringify(doc)); odd.checkpoints[0].sha256="0".repeat(64);
    const found=Runner.compare(doc,odd,source);
    assert.deepEqual([found.kind,found.checkpoint,found.difference],["state",0,null]);
});
test("numeric differences are exact and report their distance in doubles",()=>{
    // The recorded Linux/Windows Math.pow difference in state.p10f is one step apart.
    const found=Harness.stateDifference({state:{p10f:190931795304.0943}},{state:{p10f:190931795304.09433}});
    assert.deepEqual([found.path,found.category,found.ulps],["$.state.p10f","resource",1]);
    assert.equal(Harness.ulps(-0,0),0);assert.equal(Harness.ulps(-Number.MIN_VALUE,Number.MIN_VALUE),2);
    assert.equal(Harness.stateDifference({timers:[{due:10}]},{timers:[{due:11}]}).category,"pending-callback");
    assert.equal(Harness.stateDifference({state:{compFlag:0}},{state:{compFlag:1}}).category,"flag");
    assert.equal(Harness.stateDifference({state:{project1:{flag:0}}},{state:{project1:{flag:1}}}).category,"project");
    assert.equal(Harness.stateDifference({state:{ships:[1]}},{state:{ships:[2]}}).category,"array");
    assert.equal(Harness.stateDifference({draws:1},{draws:2}).category,"draw-count");
    assert.equal(Harness.stateDifference({state:{}},{state:{stocks:[1]}}).category,"array","right-only fields keep their kind");
});
test("cosmetic draws use a separate stream and never shift simulation draws",()=>{
    const trace=Traces.make("workshop"); trace.cosmetic=[0.5,0.25,0.75];
    let cosmetic;
    const right=full(trace,runner=>{
        cosmetic=runner.harness.cosmetic;
        const original=runner.global.buyWire;
        runner.global.buyWire=function(...args){
            for (let i=0;i<3;i++) cosmetic.draw("glass:shimmer",runner.harness.clock.now);
            return original.apply(this,args);
        };
    });
    // Only the input hashes differ, because the trace now records a cosmetic stream.
    assert.equal(Harness.compareTraces({...baseline,input:null},{...right,input:null}),null);
    assert.deepEqual(cosmetic.log.map(e=>[e.stream,e.ordinal]),[["cosmetic",0],["cosmetic",1],["cosmetic",2]]);
    assert.ok(right.events.every(e=>e.action!=="draw" || e.stream==="simulation"));
    assert.throws(()=>cosmetic.draw("glass:shimmer",0),/cosmetic random stream exhausted at draw 3/);
});
test("every reference draw has an inventoried call site, including names and combat setup",()=>{
    const scopes=new Set();
    for (const name of Traces.names) {
        const doc=Runner.report(Runner.run(Traces.make(name),source).result,source);
        for (const [site,{scope,draws}] of Object.entries(doc.draw_sites)) {
            assert.match(site,/^(combat|globals|projects|main)\.js:\d+:\d+$/);
            assert.ok(scope,"uninventoried draw site "+site);
            scopes.add(scope.replace(/@\d+$/,""));
            assert.ok(draws>0);
        }
        for (const event of doc.events) {
            const fields=Harness.TRACE_SCHEMA.events[event.action];
            assert.ok(fields,"unknown event "+event.action);
            for (const key of Object.keys(event)) assert.ok(key==="action" || fields.includes(key),event.action+"."+key);
        }
    }
    for (const scope of ["Ship","createBattle","generateBattleName","generateSymbol","createStock",
        "stockShop","adjustWirePrice","generateGrid","pickMove"]) assert.ok(scopes.has(scope),scope);
});

const LUA=process.env.TIM_LUA || "C:/Program Files (x86)/Lua/5.1/lua.exe";
test("the Lua recorded stream reads identical doubles and labels draws in the same events",()=>{
    assert.ok(fs.existsSync(LUA),"Set TIM_LUA to a Lua 5.1 interpreter");
    const values=[0.17,0.1+0.2,1-2**-53,Number.MIN_VALUE,0,...Traces.make("initialization").random.slice(0,3)];
    const dir=fs.mkdtempSync(path.join(os.tmpdir(),"tim-stream-"));
    try {
        const file=path.join(dir,"stream.json");
        fs.writeFileSync(file,JSON.stringify({schema:1,stream:"simulation",values}));
        const sites=["combat.js:717:22","combat.js:718:21","main.js:704:14","main.js:4574:18","main.js:1490:18"];
        const lua=labels=>{
            const out=spawnSync(LUA,[path.join(__dirname,"lua_stream_probe.lua"),file,...labels.map((s,i)=>s+"="+i*10)],
                {encoding:"utf8"});
            assert.equal(out.status,0,out.stderr);
            return JSON.parse(out.stdout);
        };
        const node=new Harness.RandomStream("simulation",values);
        sites.forEach((site,i)=>node.draw(site,i*10));
        const doc=events=>({schema:2,source_sha256:source.index.source_sha256,input:null,events,checkpoints:[]});
        const luaEvents=lua(sites);
        luaEvents.forEach((event,i)=>assert.ok(Object.is(event.value,values[i])));
        assert.equal(Harness.compareTraces(doc(node.log),doc(luaEvents)),null);
        const extra=lua([sites[0],sites[1],"main.js:1737:22",...sites.slice(2)]);
        const found=Harness.compareTraces(doc(node.log),doc(extra));
        assert.deepEqual([found.kind,found.ordinal,found.left.site,found.right.site],
            ["draw",2,"main.js:704:14","main.js:1737:22"]);
    } finally { fs.rmSync(dir,{recursive:true,force:true}); }
});

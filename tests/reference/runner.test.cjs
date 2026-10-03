"use strict";
const test=require("node:test"), assert=require("node:assert/strict");
const {Clock,Storage,encode}=require("../../Tools/reference/host.js");
const {Document}=require("../../Tools/reference/dom.cjs");
const Runner=require("../../Tools/reference/runner.cjs"), Traces=require("./traces.cjs");

test("equal-due callbacks, nested registration, cancellation and repeat queue order",()=>{
    const clock=new Clock(), seen=[];
    const interval=clock.register(()=>{
        seen.push("interval@"+clock.now);
        if (clock.now===20) clock.clear(interval);
    },10,true);
    clock.register(()=>{seen.push("first@"+clock.now);clock.register(()=>seen.push("nested@"+clock.now),0,false);},10,false);
    const cancelled=clock.register(()=>seen.push("cancelled"),10,false);
    clock.clear(cancelled);
    clock.register(()=>seen.push("second@"+clock.now),10,false);
    clock.advanceTo(30);
    assert.deepEqual(seen,["interval@10","first@10","second@10","nested@10","interval@20"]);
    assert.equal(clock.pending.size,0);
    assert.throws(()=>clock.advanceTo(29),/forward/);
});
test("callback this/arguments and runaway guard are explicit",()=>{
    const clock=new Clock(); clock.global={answer:42};
    let seen;
    clock.register(function(arg){seen=[this.answer,arg];},2,false,["value"]);
    clock.advanceTo(2); assert.deepEqual(seen,[42,"value"]);
    clock.register(()=>{},0,true);
    assert.throws(()=>clock.advanceTo(3,()=>{},4),/budget/);
});
test("storage string semantics, stable node identity, selection and disabled click",()=>{
    const storage=new Storage();
    assert.equal(storage.getItem("missing"),null);
    storage.setItem("number",3); assert.equal(storage.getItem("number"),"3");
    storage.removeItem("number"); assert.equal(storage.length,0);
    const doc=new Document({tag:"#document",attrs:{},children:[
        {tag:"select",attrs:{id:"risk"},children:[
            {tag:"option",attrs:{value:"low"},children:[]},
            {tag:"option",attrs:{value:"med"},children:[]}
        ]}
    ]},()=>{throw new Error("No inline handler expected");});
    const select=doc.getElementById("risk");
    assert.equal(select,doc.getElementById("risk")); assert.equal(select.value,"low");
    select.value="med"; assert.equal(select.value,"med");
    select.value="missing"; assert.equal(select.value,"");
    assert.equal(doc.getElementById("absent"),null);
    const parent=doc.createElement("div"), button=doc.createElement("button");
    parent.id="parent";doc.root.appendChild(parent);button.id="button";parent.appendChild(button);
    let count=0;button.onclick=()=>count++;
    button.disabled=true;button.click();assert.equal(count,0);
    button.disabled=false;button.click();assert.equal(count,1);
    parent.removeChild(button);assert.equal(doc.getElementById("button"),null);
    assert.throws(()=>parent.removeChild(button),/NotFound/);
});
test("snapshots retain nonfinite values, negative zero and array holes",()=>{
    assert.deepEqual(encode([NaN,Infinity,-0,,undefined]),[
        {$number:"NaN"},{$number:"Infinity"},{$number:"-0"},{$hole:true},{$number:"undefined"}
    ]);
    assert.deepEqual(Runner.firstDifference({a:[1,2]},{a:[1,3]}),{path:"$.a.1",left:2,right:3});
});
const source=Runner.inputs();
const evidence=JSON.parse(require("node:fs").readFileSync(require("node:path").join(Runner.ROOT,"docs/reference/browser-evidence.json"),"utf8"));
test("initialization consumes both ship resets and captures seven ordered timers",()=>{
    const x=Runner.load(Traces.make("initialization"),source);
    assert.equal(x.harness.snapshot().draws,3200);
    assert.deepEqual(x.harness.clock.describe().map(t=>[t.id,t.delay]),[
        [6,10],[1,16],[2,100],[5,100],[7,100],[3,1000],[4,2500]
    ]);
    assert.equal(x.global.document.getElementById("btnLowerProbeHaz"),x.global.btnLowerProbeHaz);
});
for (const name of Traces.names) test("fixed "+name+" trace reproduces every checkpoint",()=>{
    const trace=Traces.make(name), a=Runner.run(trace,source), b=Runner.run(trace,source);
    assert.deepEqual(Runner.report(a.result,source),Runner.report(b.result,source));
    const native=evidence.cases.find(item=>item.case===name);
    const finalHash=Runner.report(a.result,source).final_sha256;
    assert.equal(finalHash,native.final_sha256);
    assert.equal(a.result.checkpoints.length,native.checkpoints);
    assert.equal(a.result.checkpoints[0].kind,"initialization");
    assert.equal(a.result.checkpoints.at(-1).kind,"final");
    const state=a.result.final.state;
    if (name==="workshop") {
        assert.equal(state.clipperBoost,1.25);assert.equal(state.clipmakerLevel,1);
        assert.equal(a.result.final.dom.investStrat.value,"med");
        assert.equal(state.riskiness,5);assert.ok(Object.keys(a.result.final.storage).length>=5);
        assert.equal(a.global.document.getElementById("projectButton1"),null);
    }
    if (name==="cancellation") {
        const id=a.result.timerLog.find(t=>t.action==="register" && t.delay===30).id;
        assert.ok(a.result.timerLog.some(t=>t.action==="cancel" && t.id===id));
        assert.equal(a.result.timerLog.filter(t=>t.action==="fire" && t.id===id).length,12);
        assert.equal(a.result.final.dom.readout1.visibility,"visible");
    }
    if (name==="tournament") {
        assert.equal(state.tourneyInProg,0);assert.equal(state.resultsFlag,1);assert.ok(state.yomi>0);
        assert.ok(a.result.timerLog.some(t=>t.action==="register" && !t.repeat && t.delay===50));
    }
    if (name==="range") {
        const expected=["100","100","100","99","200","0","125","100"];
        const commands=a.result.checkpoints.filter(point=>point.kind==="command");
        assert.equal(commands.length,expected.length);
        for (const [i,point] of commands.entries()) {
            assert.equal(JSON.parse(point.json).dom.slider.value,expected[i]);
            const at=100*(i+1);
            const next=a.result.checkpoints.filter(point=>point.kind==="callback" && point.at===at).at(-1);
            const snapshot=JSON.parse(next.json);
            assert.equal(snapshot.dom.slider.value,expected[i]);
            assert.equal(snapshot.state.sliderPos,expected[i],"swarm read-back after input "+i);
        }
        a.global.document.getElementById("slider").setAttribute("step","any");
        assert.throws(()=>{a.global.document.getElementById("slider").value="99.5";},/outside pinned/);
    }
    if (name==="combat") {
        assert.equal(a.result.timerLog.filter(t=>t.action==="fire" && t.id===1).length,100);
        assert.ok(state.probesLostCombat>0 || state.driftersKilled>0);
        assert.notDeepEqual(state.ships,JSON.parse(a.result.checkpoints.find(t=>t.kind==="command").json).state.ships);
    }
});
test("disabling drawing preserves combat state and draw consumption",()=>{
    const on=Runner.run(Traces.make("combat",true),source), off=Runner.run(Traces.make("combat",false),source);
    const {input:onInput,...onReport}=Runner.report(on.result,source);
    const {input:offInput,...offReport}=Runner.report(off.result,source);
    assert.deepEqual(onReport,offReport);
    assert.notEqual(onInput.trace_sha256,offInput.trace_sha256);
    assert.equal(onInput.random_sha256,offInput.random_sha256);
    assert.ok(on.global.document.drawCalls>0);assert.equal(off.global.document.drawCalls,0);
});
test("random exhaustion and disallowed developer commands fail",()=>{
    assert.throws(()=>Runner.load({random:[0.5]},source),/exhausted/);
    const x=Runner.load(Traces.make("initialization"),source);
    assert.throws(()=>x.harness.run({commands:[{at:0,type:"call",name:"cheatMoney"}],until:0}),/allowlist/);
});

test("recorded native browser evidence pins current implementation and inputs",()=>{
    const fs=require("node:fs"),path=require("node:path");
    assert.equal(evidence.cases.length,7);
    for (const record of evidence.cases) {
        assert.deepEqual(record.source_sha256,source.index.source_sha256);
        assert.deepEqual(record.native_timer_probe,["first","second"]);
        assert.equal(record.matched_all_checkpoints,true);
        const name=record.case.replace(/-nodraw$/,"");
        const trace=Traces.make(name,!record.case.endsWith("-nodraw"));
        assert.equal(record.trace_sha256,Runner.sha256(JSON.stringify(trace)));
        for (const [file,sha] of Object.entries(record.tool_sha256))
            assert.equal(Runner.sha256(fs.readFileSync(path.join(Runner.ROOT,"Tools/reference",file))),sha);
    }
});
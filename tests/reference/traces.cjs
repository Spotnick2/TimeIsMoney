"use strict";
// Explicit repeat-pattern fixture expanded into finite input arrays, not native RNG.
function stream() {
    const pattern = [0.17,0.43,0.79,0.06,0.92,0.31,0.58,0.67];
    return Array.from({length:60000}, (_,i)=>pattern[i%pattern.length]);
}
const traces = {
    initialization: {until:160, commands:[]},
    workshop: {
        until:200,
        fixture:{globals:{funds:1000,standardOps:900,compFlag:1,trust:100,memory:10,investmentEngineFlag:1}},
        commands:[
            {at:0,type:"click",id:"btnMakePaperclip"},
            {at:0,type:"click",id:"btnBuyWire"},
            {at:10,type:"click",id:"btnMakeClipper"},
            {at:50,type:"click",id:"projectButton1"},
            {at:80,type:"value",id:"investStrat",value:"med"},
            {at:100,type:"click",id:"btnRaisePrice"},
            {at:120,type:"call",name:"save"},
            {at:130,type:"call",name:"load"}
        ]
    },
    cancellation: {
        until:480,
        commands:[{at:0,type:"call",name:"blink",args:[{$element:"readout1"}]}],
        // Tests bind an actual element argument rather than serializing a DOM object.
        elementCall:{name:"blink",id:"readout1"}
    },
    tournament: {
        until:1200,
        fixture:{globals:{standardOps:10000,operations:10000,memory:100,trust:100,strategyEngineFlag:1},strategies:[0]},
        commands:[
            {at:0,type:"value",id:"stratPicker",value:"0"},
            {at:100,type:"click",id:"btnNewTournament"},
            {at:110,type:"click",id:"btnRunTournament"}
        ]
    },
    combat: {
        until:1600,
        fixture:{globals:{probeCount:100000000,drifterCount:100000000,battleNameFlag:1}},
        commands:[{at:0,type:"call",name:"createBattle"}]
    }
};
function make(name, drawing = true) {
    if (!Object.hasOwn(traces,name)) throw new Error("Unknown trace: "+name);
    const trace=JSON.parse(JSON.stringify(traces[name]));
    trace.random=stream(); trace.drawing=drawing;
    return trace;
}
module.exports={names:Object.keys(traces),make};

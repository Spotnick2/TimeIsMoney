"use strict";
// Sim/CostPow.lua must be what the generator produces on the pinned reference
// profile: every integer base of each cost domain compared with this Math.pow.
const test=require("node:test"), assert=require("node:assert/strict"), fs=require("node:fs");
const CostPow=require("./cost_pow.cjs");

test("cost pow table is current for the pinned reference profile",()=>{
    const text=fs.readFileSync(CostPow.OUTPUT,"utf8");
    const profile=CostPow.PROFILE.node+" V8 "+CostPow.PROFILE.v8+" "+CostPow.PROFILE.platform+" "+CostPow.PROFILE.arch;
    // A different Node, V8 or platform computes a different platform pow: regenerate
    // and review rather than comparing against another profile's values.
    assert.ok(text.includes('profile = "'+profile+'"'),"profile changed: "+profile);
    assert.equal(text,CostPow.generate());
});

"use strict";
// Sim/CostPow.lua must be what the generator produces on the pinned reference
// profile: every integer base of each cost domain compared with this Math.pow.
const test=require("node:test"), assert=require("node:assert/strict"), fs=require("node:fs");
const CostPow=require("./cost_pow.cjs");

// The profile lines record where the values were measured; the values are compared.
// Math.pow comes from the platform C library, so a Node patch release on the same
// platform normally keeps every value, and the test still passes.
const values=text=>text.split(/\r?\n/).filter(line=>!/[Pp]rofile/.test(line)).join("\n");
test("cost pow values match this profile's Math.pow over every domain",()=>{
    assert.equal(values(fs.readFileSync(CostPow.OUTPUT,"utf8")),values(CostPow.generate()));
});

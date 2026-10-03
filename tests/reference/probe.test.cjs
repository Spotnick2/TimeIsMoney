"use strict";
// Probe/Vectors.lua must be what the generator produces from V8 and offline Lua.
const test=require("node:test"), assert=require("node:assert/strict"), fs=require("node:fs");
const Vectors=require("./probe_vectors.cjs");

test("probe vectors and workshop digest are current",()=>{
    assert.equal(fs.readFileSync(Vectors.OUTPUT,"utf8"),Vectors.generate());
});

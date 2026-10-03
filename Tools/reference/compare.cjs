"use strict";
/* Reports the first divergence between two trace documents from any runner. */
const fs=require("node:fs"), path=require("node:path");
const Runner=require("./runner.cjs");

if (require.main === module) {
    try {
        const args=process.argv.slice(2);
        if (args.length !== 2) throw new Error("Usage: node Tools/reference/compare.cjs <left-trace.json> <right-trace.json>");
        const [left,right]=args.map(file=>JSON.parse(fs.readFileSync(file,"utf8")));
        // Draw-site scopes need only the committed inventory, not the upstream cache.
        const index=JSON.parse(fs.readFileSync(path.join(Runner.ROOT,"docs/reference/inventory.json"),"utf8"));
        const found=Runner.compare(left,right,{index});
        console.log(JSON.stringify(found ? {divergent:true,...found} : {divergent:false,
            source_sha256:left.source_sha256,events:left.events.length,checkpoints:left.checkpoints.length},null,2));
        if (found) process.exitCode=1;
    } catch (error) { console.error(error.stack); process.exitCode=2; }
}

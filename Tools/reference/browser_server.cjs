"use strict";
/* Loopback-only native-DOM comparison page; verified upstream inputs stay local. */
const http=require("node:http"), fs=require("node:fs"), path=require("node:path");
const Runner=require("./runner.cjs"), Traces=require("../../tests/reference/traces.cjs");
const source=Runner.inputs(), expected=new Map();
function fixture(name) {
    const off=name.endsWith("-nodraw"), base=off ? name.slice(0,-7) : name;
    return Traces.make(base,!off);
}
function baseline(name) {
    if (!expected.has(name)) expected.set(name,Runner.run(fixture(name),source));
    return expected.get(name);
}
function send(response,body,type="application/json") {
    response.writeHead(200,{"Content-Type":type,"Cache-Control":"no-store"});
    response.end(typeof body==="string" ? body : JSON.stringify(body));
}
const server=http.createServer(async (request,response) => {
    try {
        const url=new URL(request.url,"http://127.0.0.1"), name=url.searchParams.get("case") || "initialization";
        const trace=fixture(name); // Validate the allowlisted case before any file operation.
        if (url.pathname==="/") {
            let html=source.files["index2.html"].replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi,"")
                .replace(/<link\b[^>]*>/gi,"").replace(/\bsrc\s*=\s*"[^"]*"/gi,'src=""');
            html=html.replace(/<\/head>/i,'<script src="/host.js"></script><script src="/boot.js?case='+name+'"></script></head>');
            html=html.replace(/<\/body>/i,Runner.ORDER.map(n=>'<script src="/'+n+'?v3"></script>').join("")+
                '<script>window.TIM_RESULT=TIM.run(TIM_TRACE);</script><script src="/probe.js"></script></body>');
            return send(response,html,"text/html; charset=utf-8");
        }
        if (url.pathname==="/probe.js") return send(response,fs.readFileSync(path.join(__dirname,"browser_probe.js"),"utf8"),"application/javascript");
        if (url.pathname==="/host.js") return send(response,fs.readFileSync(path.join(__dirname,"host.js"),"utf8"),"application/javascript");
        if (url.pathname==="/boot.js") {
            const config=Runner.config(source,trace.random,trace.cosmetic);
            const boot='window.TIM_ERRORS=[];window.addEventListener("error",e=>TIM_ERRORS.push(e.message));'+
                'window.TIM_TRACE='+JSON.stringify(trace)+';window.TIM=TIMHarness.create(window,'+JSON.stringify(config)+');'+
                (trace.drawing ? "" : 'CanvasRenderingContext2D.prototype.fillRect=function(){};');
            return send(response,boot,"application/javascript");
        }
        const file=url.pathname.slice(1);
        if (Runner.ORDER.includes(file)) return send(response,source.files[file],"application/javascript");
        if (url.pathname==="/expected") {
            const x=baseline(name);
            return send(response,Runner.report(x.result,source));
        }
        if (url.pathname==="/checkpoint") {
            const index=Number(url.searchParams.get("index")), x=baseline(name);
            if (!Number.isInteger(index) || index<0 || index>=x.result.checkpoints.length) throw new Error("Bad checkpoint index");
            return send(response,x.result.checkpoints[index].json);
        }
        if (url.pathname==="/evidence" && request.method==="POST") {
            let body="";
            for await (const chunk of request) {
                body+=chunk;
                if (body.length>16*1024*1024) throw new Error("Evidence payload too large");
            }
            const data=JSON.parse(body), node=Runner.report(baseline(name).result,source);
            const divergence=Runner.compare(node,{schema:node.schema,source_sha256:node.source_sha256,input:node.input,
                events:data.events,checkpoints:data.checkpoints},source);
            if (divergence || node.final_sha256!==data.final_sha256 || data.errors?.length ||
                JSON.stringify(data.native_timer_probe)!==JSON.stringify(["first","second"]) ||
                JSON.stringify(data.native_select_probe)!==JSON.stringify(["","10"]))
                return send(response,{ok:false,divergence,final_matches:node.final_sha256===data.final_sha256,errors:data.errors});
            const codeFiles=["host.js","dom.cjs","runner.cjs","parse_html.py","browser_server.cjs","browser_probe.js","check_browser.cjs"];
            const hashes=Object.fromEntries(codeFiles.map(n=>[n,Runner.sha256(fs.readFileSync(path.join(__dirname,n)))]));
            const evidence={case:name,browser:data.browser,source_sha256:source.index.source_sha256,
                tool_sha256:hashes,trace_sha256:Runner.sha256(JSON.stringify(trace)),
                random_sha256:Runner.sha256(JSON.stringify(trace.random)),
                checkpoints:node.checkpoints.length,draws:node.draws,events:node.events.length,
                events_sha256:Runner.sha256(JSON.stringify(data.events)),draw_sites:Object.keys(node.draw_sites).length,
                final_sha256:node.final_sha256,
                matched_all_checkpoints:true,native_timer_probe:data.native_timer_probe,
                native_select_probe:data.native_select_probe};
            fs.writeFileSync(path.join(source.cache,"browser-"+name+".json"),JSON.stringify(evidence,null,2)+"\n");
            return send(response,{ok:true,evidence});
        }
        response.writeHead(404); response.end("Not found");
    } catch(error) {
        response.writeHead(400,{"Content-Type":"application/json"});response.end(JSON.stringify({error:error.message}));
    }
});
server.listen(Number(process.env.TIM_PORT || 8765),"127.0.0.1",()=>console.log("Reference probe: http://127.0.0.1:"+server.address().port));

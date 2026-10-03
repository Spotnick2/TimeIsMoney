"use strict";
/* Uses an already installed browser; no npm package or browser download. */
const fs=require("node:fs"),path=require("node:path"),{spawn}=require("node:child_process");
const {ROOT,CACHE}=require("./runner.cjs"), Traces=require("../../tests/reference/traces.cjs");
const candidates=process.platform==="win32" ? [
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
] : ["/usr/bin/google-chrome","/usr/bin/google-chrome-stable","/usr/bin/chromium"];
const browser=process.env.TIM_BROWSER || candidates.find(file=>fs.existsSync(file));
if (!browser) throw new Error("Set TIM_BROWSER to an already installed Chromium browser executable.");
const cases=[...Traces.names,"combat-nodraw"];
async function main() {
    fs.mkdirSync(CACHE,{recursive:true});
    const server=spawn(process.execPath,[path.join(__dirname,"browser_server.cjs")],{
        env:{...process.env,TIM_PORT:"0"},windowsHide:true,stdio:["ignore","pipe","pipe"]
    });
    const evidence=[];
    try {
        const origin=await new Promise((resolve,reject)=>{
            let output="";
            const timeout=setTimeout(()=>reject(new Error("Probe server startup timeout")),10000);
            server.stdout.on("data",chunk=>{
                output+=chunk;
                const match=output.match(/http:\/\/127\.0\.0\.1:\d+/);
                if (match) {clearTimeout(timeout);resolve(match[0]);}
            });
            server.on("error",error=>{clearTimeout(timeout);reject(error);});
            server.on("exit",code=>{clearTimeout(timeout);reject(new Error("Probe server exited: "+code));});
        });
        const profile=path.join(ROOT,".tmp-reference-browser");
        for (const name of cases) {
            const html=await new Promise((resolve,reject)=>{
                let stdout="",stderr="";
                const child=spawn(browser,["--headless","--disable-gpu","--no-first-run",
                    "--user-data-dir="+profile,"--dump-dom","--timeout=20000",
                    "--virtual-time-budget=10000",origin+"/?case="+name],
                    {windowsHide:true,stdio:["ignore","pipe","pipe"]});
                const timeout=setTimeout(()=>{child.kill();reject(new Error("Browser probe timeout: "+name));},30000);
                child.stdout.on("data",chunk=>{stdout+=chunk;});
                child.stderr.on("data",chunk=>{stderr=(stderr+chunk).slice(-4000);});
                child.on("error",error=>{clearTimeout(timeout);reject(error);});
                child.on("close",code=>{
                    clearTimeout(timeout);
                    if (code!==0) reject(new Error("Browser exited "+code+": "+stderr));
                    else resolve(stdout);
                });
            });
            const text=html.match(/<pre id="TIM_PROBE">([\s\S]*?)<\/pre>/)?.[1];
            if (!text) throw new Error("Browser probe incomplete: "+name);
            const result=JSON.parse(text.replace(/&lt;/g,"<").replace(/&gt;/g,">")
                .replace(/&quot;/g,'"').replace(/&#39;/g,"'").replace(/&amp;/g,"&"));
            if (!result.ok) throw new Error(name+": "+JSON.stringify(result));
            if (JSON.stringify(result.evidence.native_timer_probe)!=='["first","second"]')
                throw new Error("Native timer order/cancellation mismatch: "+name);
            evidence.push(result.evidence);
            console.log(name+": "+result.evidence.checkpoints+" checkpoints and "+result.evidence.events+
                " events match native DOM; "+result.evidence.draws+" labeled draws");
        }
        fs.writeFileSync(path.join(CACHE,"browser-evidence.json"),
            JSON.stringify({schema:1,node:process.version,checked_at_utc:new Date().toISOString(),cases:evidence},null,2)+"\n");
    } finally { server.kill(); }
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});

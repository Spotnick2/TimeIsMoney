/* Run on the loopback probe page after the untouched gameplay scripts load. */
(async function () {
    const output=document.createElement("pre");
    output.id="TIM_PROBE";
    document.body.appendChild(output);
    try {
        if (!window.TIM_RESULT) throw new Error("Gameplay bootstrap failed: "+JSON.stringify(window.TIM_ERRORS));
        const sha=async text => [...new Uint8Array(await crypto.subtle.digest("SHA-256",new TextEncoder().encode(text)))]
            .map(x=>x.toString(16).padStart(2,"0")).join("");
        const checkpoints=[];
        for (const {json,...meta} of TIM_RESULT.checkpoints) checkpoints.push({...meta,sha256:await sha(json)});
        const expected=await (await fetch("/expected"+location.search)).json();
        const index=checkpoints.findIndex((item,i)=>JSON.stringify(item)!==JSON.stringify(expected.checkpoints[i]));
        if (index>=0 || checkpoints.length!==expected.checkpoints.length) {
            const reference=await (await fetch("/checkpoint"+location.search+"&index="+Math.max(0,index))).json();
            const current=JSON.parse(TIM_RESULT.checkpoints[Math.max(0,index)].json);
            function diff(a,b,path="$") {
                if (Object.is(a,b)) return null;
                if (!a || !b || typeof a!=="object" || typeof b!=="object") return {path,left:a,right:b};
                for (const k of [...new Set([...Object.keys(a),...Object.keys(b)])].sort()) {
                    const found=diff(a[k],b[k],path+"."+k); if (found) return found;
                }
                return null;
            }
            output.textContent=JSON.stringify({ok:false,index,difference:diff(reference,current),errors:TIM_ERRORS});
            return;
        }
        const native_timer_probe=await new Promise(resolve=>{
            const seen=[], timers=TIM.nativeTimers;
            const a=timers.setTimeout(()=>seen.push("first"),0);
            const dead=timers.setTimeout(()=>seen.push("cancelled"),0);
            timers.clearTimeout(dead);
            timers.setTimeout(()=>seen.push("second"),0);
            timers.setTimeout(()=>resolve(seen),20);
        });
        const body={browser:navigator.userAgent,checkpoints,errors:TIM_ERRORS,native_timer_probe,
            final_sha256:await sha(JSON.stringify(TIMHarness.encode(TIM_RESULT.final)))};
        const result=await (await fetch("/evidence"+location.search,{
            method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)
        })).json();
        output.textContent=JSON.stringify(result);
    } catch(error) { output.textContent=JSON.stringify({ok:false,error:error.message,errors:window.TIM_ERRORS}); }
})();

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
        // The server serves only the verified source bytes recorded in the Node report.
        const browser={schema:expected.schema,source_sha256:expected.source_sha256,input:expected.input,events:TIM_RESULT.events,checkpoints};
        const found=TIMHarness.compareTraces(expected,browser);
        if (found) {
            if (found.kind==="state") {
                const reference=await (await fetch("/checkpoint"+location.search+"&index="+found.checkpoint)).json();
                found.difference=TIMHarness.stateDifference(reference,JSON.parse(TIM_RESULT.checkpoints[found.checkpoint].json));
            }
            output.textContent=JSON.stringify({ok:false,divergence:found,errors:TIM_ERRORS});
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
        // Native selectedness: an unmatched value empties a select; inserting an
        // option then selects the first option.
        const select=document.createElement("select");
        for (const value of ["10","0"]) { const o=document.createElement("option"); o.value=value; select.appendChild(o); }
        document.body.appendChild(select);
        select.value="3";
        const emptied=select.value, inserted=document.createElement("option");
        inserted.value=1; select.appendChild(inserted);
        const native_select_probe=[emptied,select.value];
        select.remove();
        const body={browser:navigator.userAgent,checkpoints,events:TIM_RESULT.events,errors:TIM_ERRORS,native_timer_probe,
            native_select_probe,
            final_sha256:await sha(JSON.stringify(TIMHarness.encode(TIM_RESULT.final)))};
        const result=await (await fetch("/evidence"+location.search,{
            method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify(body)
        })).json();
        output.textContent=JSON.stringify(result);
    } catch(error) { output.textContent=JSON.stringify({ok:false,error:error.message,errors:window.TIM_ERRORS}); }
})();

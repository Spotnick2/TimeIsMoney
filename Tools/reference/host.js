/* Developer-only logical host shared by Node and the native-DOM browser probe. */
(function (root, factory) {
    const api = factory();
    if (typeof module === "object" && module.exports) module.exports = api;
    else root.TIMHarness = api;
})(globalThis, function () {
    "use strict";
    class Clock {
        constructor() { this.now = 0; this.nextId = 1; this.order = 0; this.pending = new Map(); this.log = []; }
        register(fn, delay, repeat, args = []) {
            if (typeof fn !== "function") throw new Error("String timers are outside the pinned host contract");
            if (!Number.isFinite(delay) || delay < 0) throw new Error("Expected a finite nonnegative timer delay");
            const id = this.nextId++;
            const timer = { id, fn, delay, repeat, args, due: this.now + delay, order: this.order++ };
            this.pending.set(id, timer);
            this.log.push({ action: "register", at: this.now, id, delay, repeat, due: timer.due });
            return id;
        }
        clear(id) {
            this.log.push({ action: "cancel", at: this.now, id, existed: this.pending.has(id) });
            this.pending.delete(id);
        }
        describe() {
            return [...this.pending.values()].sort((a,b) => a.due-b.due || a.order-b.order)
                .map(({id,delay,repeat,due,order}) => ({id,delay,repeat,due,order}));
        }
        advanceTo(target, after = () => {}, maxCallbacks = 100000) {
            if (!Number.isFinite(target) || target < this.now) throw new Error("Logical time must move forward");
            let count = 0;
            while (true) {
                const timer = [...this.pending.values()].sort((a,b) => a.due-b.due || a.order-b.order)[0];
                if (!timer || timer.due > target) break;
                if (++count > maxCallbacks) throw new Error("Callback budget exceeded");
                this.now = timer.due;
                if (!timer.repeat) this.pending.delete(timer.id);
                this.log.push({ action: "fire", at: this.now, id: timer.id });
                timer.fn.apply(this.global, timer.args);
                if (timer.repeat && this.pending.has(timer.id)) {
                    timer.due = this.now + timer.delay;
                    timer.order = this.order++;
                }
                after({ kind: "callback", at: this.now, id: timer.id });
            }
            this.now = target;
        }
    }

    class Storage {
        constructor(seed = {}) { this.values = new Map(Object.entries(seed).map(([k,v]) => [k,String(v)])); }
        get length() { return this.values.size; }
        key(i) { return [...this.values.keys()][i] ?? null; }
        getItem(key) { return this.values.get(String(key)) ?? null; }
        setItem(key, value) { this.values.set(String(key), String(value)); }
        removeItem(key) { this.values.delete(String(key)); }
        clear() { this.values.clear(); }
    }

    class AudioHost {
        constructor() { this.src = ""; this.listeners = new Map(); this.playCount = 0; }
        addEventListener(type, fn) {
            const callbacks = this.listeners.get(type) || [];
            if (!callbacks.includes(fn)) callbacks.push(fn);
            this.listeners.set(type, callbacks);
        }
        ready() { for (const fn of this.listeners.get("canplaythrough") || []) fn.call(this); }
        play() { this.playCount++; return Promise.resolve(); }
    }

    // Canonicalize numbers and omit functions/native nodes. Keep array order and
    // distinguish holes/undefined/nonfinite numbers rather than JSON coercing them.
    function encode(value, ancestors = []) {
        if (value === undefined) return { $number: "undefined" };
        if (typeof value === "number") {
            if (Object.is(value, -0)) return { $number: "-0" };
            if (!Number.isFinite(value)) return { $number: String(value) };
            return value;
        }
        if (typeof value === "function") return undefined;
        if (value === null || typeof value !== "object") return value;
        if (typeof value.nodeType === "number") return { $node: value.id || value.nodeName };
        if (ancestors.includes(value)) throw new Error("Unsupported cyclic simulation value");
        const next = ancestors.concat([value]);
        if (Array.isArray(value)) return Array.from({length:value.length}, (_,i) =>
            i in value ? encode(value[i], next) : {$hole:true});
        const result = {};
        for (const key of Object.keys(value).sort()) {
            if (["element", "title", "description", "priceTag"].includes(key)) continue;
            const encoded = encode(value[key], next);
            if (encoded !== undefined) result[key] = encoded;
        }
        return result;
    }

    function create(global, config) {
        const clock = new Clock(), audio = [];
        clock.global = global;
        let draws = 0;
        const values = config.random;
        if (!Array.isArray(values) || !values.length || values.some(v => !Number.isFinite(v) || v < 0 || v >= 1))
            throw new Error("An explicit finite random stream in [0,1) is required");
        const nativeTimers = { setTimeout: global.setTimeout?.bind(global), clearTimeout: global.clearTimeout?.bind(global) };
        global.setInterval = (fn,delay,...args) => clock.register(fn,delay,true,args);
        global.setTimeout = (fn,delay,...args) => clock.register(fn,delay,false,args);
        global.clearInterval = global.clearTimeout = id => clock.clear(id);
        global.Math.random = () => {
            if (draws >= values.length) throw new Error("Random stream exhausted at draw " + draws);
            return values[draws++];
        };
        const realLocaleString = global.Number.prototype.toLocaleString;
        global.Number.prototype.toLocaleString = function (...args) {
            return realLocaleString.call(this, args[0] || "en-US", args[1]);
        };
        global.Audio = function () { const a = new AudioHost(); audio.push(a); return a; };
        const storage = new Storage(config.storage);
        // Window.localStorage is an accessor in browsers.
        Object.defineProperty(global, "localStorage", {configurable:true, value:storage});
        global.confirm = () => { throw new Error("Restart confirmation needs an explicit future host decision"); };
        const checkpoints = [];
        function snapshot() {
            const state = {};
            for (const name of config.stateNames) {
                const value = global[name];
                if (typeof value === "function" || value === undefined) continue;
                if (value && typeof value === "object" &&
                    (typeof value.nodeType === "number" || audio.includes(value))) continue;
                state[name] = encode(value);
            }
            const ids = [...new Set(config.domIds.concat((global.activeProjects || []).map(p => p.id)))].sort();
            const dom = {};
            for (const id of ids) {
                const node = global.document.getElementById(id);
                if (!node) { dom[id] = null; continue; }
                dom[id] = { display: node.style.display, visibility: node.style.visibility };
                if (node.value !== undefined) dom[id].value = node.value;
                if (node.disabled !== undefined) dom[id].disabled = node.disabled;
                if (/^readout[1-5]$/.test(id)) dom[id].html = node.innerHTML;
            }
            const stored = {};
            for (let i=0; i<storage.length; i++) {
                const key = storage.key(i);
                // The reference saves JSON; normalize key order for browser/VM parity.
                stored[key] = encode(JSON.parse(storage.getItem(key)));
            }
            return { state, dom, storage:stored, timers:clock.describe(), draws };
        }
        function checkpoint(meta) {
            checkpoints.push({ ...meta, json:JSON.stringify(encode(snapshot())) });
        }
        function fixture(setup = {}) {
            for (const [key,value] of Object.entries(setup.globals || {})) {
                if (!config.stateNames.includes(key)) throw new Error("Unknown fixture global: " + key);
                global[key] = value;
            }
            for (const [key,value] of Object.entries(setup.projectFlags || {})) {
                if (!/^project\d+[a-z]?$/.test(key) || !global[key]) throw new Error("Unknown fixture project");
                global[key].flag = value;
            }
            if (setup.strategies) global.strats = setup.strategies.map(i => global.allStrats[i]);
            checkpoint({kind:"fixture",at:clock.now});
        }
        function command(command) {
            const node = command.id && global.document.getElementById(command.id);
            if (command.type === "click") {
                if (!node || typeof node.click !== "function") throw new Error("Unknown clickable ID");
                node.click(); // Disabled controls follow native click semantics.
            } else if (command.type === "value") {
                if (!node || node.value === undefined) throw new Error("Unknown value-bearing ID");
                node.value = command.value;
            } else if (command.type === "call") {
                if (!config.calls.includes(command.name) || typeof global[command.name] !== "function")
                    throw new Error("Call outside explicit developer fixture allowlist");
                const args = (command.args || []).map(value => value && value.$element ?
                    global.document.getElementById(value.$element) : value);
                global[command.name](...args);
            } else if (command.type === "media-ready") {
                for (const a of audio) a.ready();
            } else throw new Error("Unknown command type");
            checkpoint({kind:"command",at:clock.now,type:command.type,id:command.id,name:command.name});
        }
        function run(trace) {
            checkpoint({kind:"initialization",at:0});
            fixture(trace.fixture);
            for (const item of trace.commands || []) {
                clock.advanceTo(item.at, checkpoint, config.maxCallbacks);
                command(item);
            }
            clock.advanceTo(trace.until, checkpoint, config.maxCallbacks);
            checkpoint({kind:"final",at:clock.now});
            return { checkpoints, timerLog:clock.log, final:snapshot(), draws };
        }
        return { clock, audio, storage, snapshot, run, nativeTimers };
    }
    return { Clock, Storage, AudioHost, encode, create };
});

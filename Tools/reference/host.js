/* Developer-only logical host shared by Node and the native-DOM browser probe. */
(function (root, factory) {
    const api = factory();
    if (typeof module === "object" && module.exports) module.exports = api;
    else root.TIMHarness = api;
})(globalThis, function () {
    "use strict";
    class Clock {
        constructor(log = []) { this.now = 0; this.nextId = 1; this.order = 0; this.pending = new Map(); this.log = log; }
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
        next() { return [...this.pending.values()].sort((a,b) => a.due-b.due || a.order-b.order)[0]; }
        advanceTo(target, after = () => {}, maxCallbacks = 100000) {
            if (!Number.isFinite(target) || target < this.now) throw new Error("Logical time must move forward");
            let count = 0;
            while (true) {
                const timer = this.next();
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

    // Finite recorded values in [0,1). Every draw is logged with its stream name,
    // zero-based ordinal, logical time and call-site label; exhaustion never wraps.
    class RandomStream {
        constructor(name, values, log = []) {
            if (!Array.isArray(values) || !values.length || values.some(v => !Number.isFinite(v) || v < 0 || v >= 1))
                throw new Error("An explicit finite random stream in [0,1) is required");
            this.name = name; this.values = values; this.cursor = 0; this.log = log;
        }
        draw(site, at) {
            if (this.cursor >= this.values.length)
                throw new Error(this.name + " random stream exhausted at draw " + this.cursor + " (" + site + ")");
            const value = this.values[this.cursor];
            this.log.push({ action: "draw", at, stream: this.name, ordinal: this.cursor++, site, value });
            return value;
        }
    }

    // First stack frame outside this host, as file:line:column with URL queries
    // removed, so VM filenames and served script URLs label a draw identically.
    function callSite(stack) {
        for (const line of String(stack).split("\n").slice(1)) {
            const match = /\(?([^\s()]+):(\d+):(\d+)\)?\s*$/.exec(line);
            if (!match) continue;
            const file = match[1].replace(/[?#].*$/, "").split(/[\\/]/).pop();
            if (file !== "host.js") return file + ":" + match[2] + ":" + match[3];
        }
        return "unknown";
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
        // One ordered log interleaves timer events, simulation draws and checkpoints.
        const events = [], clock = new Clock(events), audio = [];
        clock.global = global;
        const random = new RandomStream("simulation", config.random, events);
        // The pinned source has no cosmetic randomness; this separate stream exists so
        // later presentation draws cannot shift simulation ordinals or outcomes.
        const cosmetic = config.cosmetic ? new RandomStream("cosmetic", config.cosmetic) : null;
        const nativeTimers = { setTimeout: global.setTimeout?.bind(global), clearTimeout: global.clearTimeout?.bind(global) };
        global.setInterval = (fn,delay,...args) => clock.register(fn,delay,true,args);
        global.setTimeout = (fn,delay,...args) => clock.register(fn,delay,false,args);
        global.clearInterval = global.clearTimeout = id => clock.clear(id);
        global.Math.random = () => {
            // The labeled caller is the second frame; a short stack keeps draws cheap.
            const limit = Error.stackTraceLimit;
            Error.stackTraceLimit = 4;
            const stack = new Error().stack;
            Error.stackTraceLimit = limit;
            return random.draw(callSite(stack), clock.now);
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
            return { state, dom, storage:stored, timers:clock.describe(), draws:random.cursor };
        }
        function checkpoint(meta) {
            events.push({ action:"checkpoint", index:checkpoints.length, ...meta });
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
            return { checkpoints, events, timerLog:events.filter(e => TIMER_ACTIONS.includes(e.action)),
                     final:snapshot(), draws:random.cursor };
        }
        return { clock, random, cosmetic, audio, storage, snapshot, run, nativeTimers };
    }

    const TIMER_ACTIONS = ["register", "cancel", "fire"];
    // Emerging runner-neutral trace contract. A Lua runner emits the same events and
    // checkpoint sections; field order inside events is not significant.
    const TRACE_SCHEMA = {
        version: 2,
        events: {
            register: ["at", "id", "delay", "repeat", "due"],
            cancel: ["at", "id", "existed"],
            fire: ["at", "id"],
            draw: ["at", "stream", "ordinal", "site", "value"],
            checkpoint: ["index", "kind", "at", "type", "id", "name"]
        },
        checkpoint: ["state", "dom", "storage", "timers", "draws"],
        commands: { click: ["id"], value: ["id", "value"], call: ["name", "args"], "media-ready": [] },
        categories: ["resource", "flag", "array", "project", "entity", "value",
                     "pending-callback", "draw-count", "host-dom", "reference-storage"]
    };

    // Category of a differing checkpoint field, for first-divergence reports.
    function classify(path, value) {
        const [, section, name] = path.split(".");
        if (section === "timers") return "pending-callback";
        if (section === "draws") return "draw-count";
        if (section === "dom") return "host-dom";
        if (section === "storage") return "reference-storage";
        if (/^project\d+[a-z]?$|^activeProjects$/.test(name)) return "project";
        if (/flag/i.test(name)) return "flag";
        if (Array.isArray(value)) return "array";
        if (typeof value === "number") return "resource";
        if (value && typeof value === "object") return value.$number ? "resource" : "entity";
        return "value";
    }
    // Distance in representable doubles, reported as evidence; never a tolerance.
    function ulps(a, b) {
        if (typeof a !== "number" || typeof b !== "number" || !Number.isFinite(a) || !Number.isFinite(b)) return null;
        const view = new DataView(new ArrayBuffer(8)), ordered = x => {
            view.setFloat64(0, x); const bits = view.getBigInt64(0);
            return bits < 0n ? -(bits & 0x7fffffffffffffffn) : bits;
        };
        const d = ordered(a) - ordered(b);
        return Number(d < 0n ? -d : d);
    }
    function firstDifference(left, right, at = "$") {
        if (Object.is(left, right)) return null;
        if (!left || !right || typeof left !== "object" || typeof right !== "object")
            return { path: at, left, right };
        for (const key of [...new Set([...Object.keys(left), ...Object.keys(right)])].sort()) {
            const diff = firstDifference(left[key], right[key], at + "." + key);
            if (diff) return diff;
        }
        return null;
    }
    function stateDifference(left, right) {
        const diff = firstDifference(left, right);
        if (!diff) return null;
        const [, section, name] = diff.path.split(".");
        const value = section && name !== undefined ? left[section]?.[name] ?? right[section]?.[name] : undefined;
        return { ...diff, category: classify(diff.path, value), ulps: ulps(diff.left, diff.right) };
    }

    // A comparable document has this schema and exactly one checkpoint event per
    // checkpoint, in index order, so walking the events covers every checkpoint.
    function validateTrace(doc, side) {
        if (!doc || doc.schema !== TRACE_SCHEMA.version)
            throw new Error(side + " trace schema " + doc?.schema + " is not supported (expected " + TRACE_SCHEMA.version + ")");
        if (!Array.isArray(doc.events) || !Array.isArray(doc.checkpoints))
            throw new Error(side + " trace needs events and checkpoints arrays");
        let next = 0;
        for (const event of doc.events) if (event.action === "checkpoint" && event.index !== next++)
            throw new Error(side + " checkpoint events must cover checkpoints in index order");
        if (next !== doc.checkpoints.length)
            throw new Error(side + " trace has " + doc.checkpoints.length + " checkpoints but " + next + " checkpoint events");
    }

    // Exact first divergence between two trace documents
    // {schema, source_sha256, input, events, checkpoints[{...meta, sha256?, json?}]}.
    // Events are compared in order, so an extra draw, a different branch's draw site
    // or a reordered callback is reported where it first happens, before later state.
    function compareTraces(left, right, context = 8) {
        validateTrace(left, "left"); validateTrace(right, "right");
        const base = { source_sha256: { left: left.source_sha256, right: right.source_sha256 },
                       input: { left: left.input, right: right.input } };
        if (!left.source_sha256 || firstDifference(left.source_sha256, right.source_sha256))
            return { ...base, kind: "source", event: null, after: null };
        let after = null;
        const length = Math.max(left.events.length, right.events.length);
        for (let i = 0; i < length; i++) {
            const a = left.events[i], b = right.events[i];
            const found = (kind, extra) => ({ ...base, kind, event: i, after,
                left: a ?? null, right: b ?? null, ...extra,
                context: { left: left.events.slice(Math.max(0, i - context), i),
                           right: right.events.slice(Math.max(0, i - context), i) } });
            if (!a || !b) return found("length");
            if (a.action === "draw" || b.action === "draw") {
                const diff = firstDifference(a, b);
                if (diff) return found("draw", { ordinal: (a.action === "draw" ? a : b).ordinal, field: diff.path });
                continue;
            }
            if (a.action !== "checkpoint" || b.action !== "checkpoint") {
                const diff = firstDifference(a, b);
                if (diff) return found(TIMER_ACTIONS.includes(a.action) || TIMER_ACTIONS.includes(b.action) ?
                    "timer" : "event", { field: diff.path });
                continue;
            }
            const meta = point => { const { sha256, json, ...rest } = point; return rest; };
            const pa = left.checkpoints[a.index], pb = right.checkpoints[b.index];
            if (!pa || !pb) return found("checkpoint", { field: "$.index" });
            const metaDiff = firstDifference(a, b) || firstDifference(meta(pa), meta(pb));
            if (metaDiff) return found("checkpoint", { field: metaDiff.path });
            const hashed = pa.sha256 !== undefined && pb.sha256 !== undefined;
            if (hashed && pa.sha256 === pb.sha256) {
                // Equal hashes need no parse.
            } else if (pa.json !== undefined && pb.json !== undefined) {
                const diff = pa.json === pb.json ? null : stateDifference(JSON.parse(pa.json), JSON.parse(pb.json));
                if (diff) return found("state", { checkpoint: a.index, difference: diff });
            } else if (hashed) {
                return found("state", { checkpoint: a.index, difference: null,
                    sha256: { left: pa.sha256, right: pb.sha256 } });
            } else {
                throw new Error("Checkpoint " + a.index + " needs JSON or SHA-256 on both sides to compare");
            }
            after = { index: a.index, ...meta(pa) };
        }
        return null;
    }
    return { Clock, RandomStream, Storage, AudioHost, TRACE_SCHEMA, callSite, encode, classify, ulps,
             firstDifference, stateDifference, validateTrace, compareTraces, create };
});

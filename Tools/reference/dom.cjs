"use strict";
/* Focused DOM model for verified reference inputs. No fabricated lookup nodes. */
const VOID = new Set("area base br col embed hr img input link meta param source track wbr".split(" "));
function decode(text) {
    return String(text).replace(/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos|nbsp);?/gi, (_,key) => {
        if (key[0] === "#") return String.fromCodePoint(key[1].toLowerCase()==="x" ? parseInt(key.slice(2),16) : +key.slice(1));
        return ({amp:"&",lt:"<",gt:">",quot:'"',apos:"'",nbsp:"\u00a0"})[key.toLowerCase()];
    });
}
function escape(text) {
    return String(text).replace(/&/g,"&amp;").replace(/\u00a0/g,"&nbsp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}
function attributes(text) {
    const attrs = {};
    for (const m of text.matchAll(/([^\s=/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g))
        attrs[m[1].toLowerCase()] = decode(m[2] ?? m[3] ?? m[4] ?? "");
    return attrs;
}
class Node {
    constructor(document, tag, attrs = {}, text) {
        this.ownerDocument = document; this.tag = tag; this.attrs = {...attrs};
        this.nodeType = tag === "#text" ? 3 : tag === "#document" ? 9 : 1;
        this.nodeName = tag.toUpperCase(); this.childNodes = []; this.parentNode = null;
        this.data = text; this._value = attrs.value ?? ""; this._selectedValue = undefined;
        const styles = {};
        this.style = new Proxy(styles, {
            get: (obj,key) => obj[key] ?? "",
            set: (obj,key,value) => { obj[key] = String(value); return true; }
        });
        for (const entry of (attrs.style || "").split(";")) {
            const colon = entry.indexOf(":");
            if (colon >= 0) this.style[entry.slice(0,colon).trim().replace(/-([a-z])/g,(_,c)=>c.toUpperCase())] = entry.slice(colon+1).trim();
        }
        if (tag === "canvas") {
            this.width = 300; this.height = 150;
            this._context = {fillStyle:"#000000", fillRect: (...args) => {
                if (args.length !== 4) throw new Error("Unexpected canvas fillRect");
                if (document.drawing !== false) document.drawCalls++;
            }};
        }
    }
    get id() { return this.attrs.id || ""; }
    set id(v) { this.attrs.id = String(v); }
    get firstChild() { return this.childNodes[0] || null; }
    get className() { return this.attrs.class || ""; }
    set className(v) { this.attrs.class = String(v); }
    get disabled() { return ["button","input","select","option"].includes(this.tag) ? "disabled" in this.attrs : undefined; }
    set disabled(v) { if (v) this.attrs.disabled = ""; else delete this.attrs.disabled; }
    get options() { return this.tag === "select" ? this.childNodes.filter(n=>n.tag==="option") : undefined; }
    get value() {
        if (this.tag === "select") {
            if (this._selectedValue !== undefined) return this._selectedValue;
            const option = this.options.find(n=>"selected" in n.attrs) || this.options[0];
            return option?.value ?? "";
        }
        if (this.tag === "option") return this.attrs.value ?? this.textContent.trim();
        if (["input","button"].includes(this.tag)) return this._value;
        return undefined;
    }
    set value(value) {
        value = String(value);
        if (this.tag === "select") this._selectedValue = this.options.some(n=>n.value===value) ? value : "";
        else if (this.tag === "option") this.attrs.value = value;
        else if (this.tag === "input" && this.attrs.type === "range") {
            const min = Number(this.attrs.min ?? 0), max = Number(this.attrs.max ?? 100);
            const n = Number(value);
            this._value = String(Math.max(min,Math.min(max,Number.isFinite(n) ? n : (min+max)/2)));
        } else if (["input","button"].includes(this.tag)) this._value = value;
        else throw new Error("Unsupported value setter: " + this.tag);
    }
    get textContent() { return this.nodeType === 3 ? this.data : this.childNodes.map(n=>n.textContent).join(""); }
    set textContent(text) { this._replaceChildren(); this.appendChild(this.ownerDocument.createTextNode(String(text))); }
    get innerHTML() { return this.childNodes.map(n=>n.outerHTML).join(""); }
    set innerHTML(html) {
        this._replaceChildren();
        const stack = [this];
        for (const m of String(html).matchAll(/<!--[\s\S]*?-->|<\/?[^>]+>|[^<]+|</g)) {
            const token = m[0];
            if (token.startsWith("<!--")) continue;
            if (/^<\//.test(token)) {
                const tag = token.match(/^<\/([\w-]+)/)?.[1]?.toLowerCase();
                const index = stack.findLastIndex(n=>n.tag===tag);
                if (index > 0) stack.splice(index);
            } else if (/^<[\w]/.test(token)) {
                const match = token.match(/^<([\w-]+)([\s\S]*?)\/?>$/);
                const tag = match[1].toLowerCase();
                const node = new Node(this.ownerDocument,tag,attributes(match[2]));
                stack.at(-1).appendChild(node);
                if (!VOID.has(tag)) stack.push(node);
            } else stack.at(-1).appendChild(this.ownerDocument.createTextNode(decode(token)));
        }
    }
    get outerHTML() {
        if (this.nodeType === 3) return escape(this.data);
        const attrs = Object.entries(this.attrs).map(([k,v]) => " "+k+'="'+escape(v).replace(/"/g,"&quot;")+'"').join("");
        return "<"+this.tag+attrs+">"+(VOID.has(this.tag) ? "" : this.innerHTML+"</"+this.tag+">");
    }
    _replaceChildren() { for (const n of this.childNodes) n.parentNode = null; this.childNodes = []; }
    appendChild(node) {
        if (node.parentNode) node.parentNode.removeChild(node);
        node.parentNode = this; this.childNodes.push(node); return node;
    }
    insertBefore(node, reference) {
        if (reference == null) return this.appendChild(node);
        if (!this.childNodes.includes(reference)) throw new Error("NotFoundError: insertBefore");
        if (node.parentNode) node.parentNode.removeChild(node);
        node.parentNode = this; this.childNodes.splice(this.childNodes.indexOf(reference),0,node); return node;
    }
    removeChild(node) {
        const index = this.childNodes.indexOf(node);
        if (index < 0) throw new Error("NotFoundError: removeChild");
        this.childNodes.splice(index,1); node.parentNode = null; return node;
    }
    setAttribute(key,value) { this.attrs[String(key).toLowerCase()] = String(value); }
    getAttribute(key) { return this.attrs[String(key).toLowerCase()] ?? null; }
    getContext(type) { if (this.tag !== "canvas" || type !== "2d") throw new Error("Unsupported canvas context"); return this._context; }
    click() {
        if (this.disabled) return;
        const handler = this.onclick || (this.attrs.onclick && this.ownerDocument.compile(this.attrs.onclick));
        if (handler) handler.call(this, {type:"click",target:this});
    }
}
class Document {
    constructor(tree, compile) {
        this.compile = compile; this.drawCalls = 0;
        const build = item => {
            if ("text" in item) return this.createTextNode(item.text);
            const node = new Node(this,item.tag,item.attrs);
            for (const child of item.children) node.appendChild(build(child));
            return node;
        };
        this.root = build(tree);
    }
    createElement(tag) { return new Node(this,String(tag).toLowerCase()); }
    createTextNode(text) { return new Node(this,"#text",{},String(text)); }
    getElementById(id) {
        id = String(id);
        function find(node) {
            if (node.id === id && node.nodeType === 1) return node;
            for (const child of node.childNodes) { const found = find(child); if (found) return found; }
            return null;
        }
        return find(this.root);
    }
}
module.exports = {Document, Node};

// Waits for the check page's #result text through the Chrome DevTools protocol: node script/web_input_read.mjs debug_port
const port = process.argv[2];
const deadline = Date.now() + 60000;
const sleep = ms => new Promise(r => setTimeout(r, ms));
let page = null;
while (!page && Date.now() < deadline) {
  try { page = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === "page"); } catch (e) { /* not up yet */ }
  if (!page) await sleep(300);
}
if (!page) { console.log("FAIL no page"); process.exit(1); }
const ws = new WebSocket(page.webSocketDebuggerUrl);
await new Promise(r => ws.addEventListener("open", r));
let id = 0;
const pending = new Map();
ws.addEventListener("message", m => { const d = JSON.parse(m.data); if (pending.has(d.id)) { pending.get(d.id)(d); pending.delete(d.id); } });
const evaluate = expression => new Promise(r => { pending.set(++id, r); ws.send(JSON.stringify({ id, method: "Runtime.evaluate", params: { expression, returnByValue: true } })); });
let text = "running";
while (Date.now() < deadline) {
  const r = await evaluate('document.getElementById("result") ? document.getElementById("result").textContent : "loading"');
  text = r.result && r.result.result ? r.result.result.value : "error";
  if (text !== "running" && text !== "loading") break;
  await sleep(300);
}
console.log(text);
ws.close();
process.exit(text.startsWith("PASS") ? 0 : 1);

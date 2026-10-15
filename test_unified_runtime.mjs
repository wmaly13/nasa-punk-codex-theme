import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath, pathToFileURL } from "node:url";

const packageRoot = path.dirname(fileURLToPath(import.meta.url));
const taskRoot = path.dirname(packageRoot);
const upstreamArg = process.argv.indexOf("--upstream");
if (upstreamArg >= 0 && !process.argv[upstreamArg + 1]) throw new Error("--upstream requires the pinned source repository path");
const upstreamRoot = upstreamArg >= 0 ? path.resolve(process.argv[upstreamArg + 1])
  : path.join(taskRoot, ".support", "upstream", "Codex-Dream-Skin-1.5.20");
const upstream = path.join(upstreamRoot, "windows");
const rendererAssets = path.join(upstream, "assets");
const sourceApi = path.join(packageRoot, "lone-star-runtime-api.mjs");
const sourceStyle = path.join(packageRoot, "lone-star-style.mjs");
const sourceAdapter = path.join(packageRoot, "lone-star-adapter.mjs");
const nasaThemeId = "nasa-punk-device-light";
const expectedOriginalStyleHash = "caf353d4e18b3f5234ed499ea686fc95d4d7dc72fed43e084cc913af6a058724";

const nodeVersion = process.version;
assert.ok(Number.parseInt(nodeVersion.slice(1), 10) >= 22, `Node 22+ required, got ${nodeVersion}`);
assert.ok((await fs.stat(rendererAssets)).isDirectory(), `pinned upstream assets missing: ${rendererAssets}`);

class MockStyle {
  values = new Map();
  getPropertyValue(name) { return this.values.get(name) ?? ""; }
  setProperty(name, value) { this.values.set(name, String(value)); }
  removeProperty(name) { this.values.delete(name); }
  [Symbol.iterator]() { return this.values.keys(); }
}

class MockElement {
  constructor(tagName, ownerDocument) {
    this.tagName = tagName.toUpperCase();
    this.ownerDocument = ownerDocument;
    this.attributesByName = new Map();
    this.style = new MockStyle();
    this.children = [];
    this.parentElement = null;
    this.isConnected = false;
    this.id = "";
    this.textContent = "";
    this.className = "";
    this.localName = tagName.toLowerCase();
    this.classList = { contains: () => false, add: () => {}, remove: () => {} };
  }
  get attributes() {
    return [...this.attributesByName].map(([name, value]) => ({ name, value }));
  }
  getAttribute(name) { return this.attributesByName.get(name) ?? null; }
  setAttribute(name, value) { this.attributesByName.set(name, String(value)); }
  removeAttribute(name) { this.attributesByName.delete(name); }
  appendChild(node) {
    if (node.parentElement) node.remove();
    this.children.push(node);
    node.parentElement = this;
    node.isConnected = true;
    return node;
  }
  remove() {
    if (this.parentElement) {
      const index = this.parentElement.children.indexOf(this);
      if (index >= 0) this.parentElement.children.splice(index, 1);
    }
    this.parentElement = null;
    this.isConnected = false;
  }
  querySelector() { return null; }
  querySelectorAll() { return []; }
  matches() { return false; }
  closest() { return null; }
}

function makeRendererContext() {
  const document = {
    adoptedStyleSheets: undefined,
    listeners: new Map(),
    createElement(tagName) { return new MockElement(tagName, document); },
    getElementById(id) {
      const visit = (node) => {
        if (node.id === id) return node;
        for (const child of node.children) {
          const found = visit(child);
          if (found) return found;
        }
        return null;
      };
      return visit(document.documentElement);
    },
    querySelector() { return null; },
    querySelectorAll() { return []; },
    addEventListener(name, fn) { document.listeners.set(name, fn); },
    removeEventListener(name) { document.listeners.delete(name); },
  };
  document.documentElement = new MockElement("html", document);
  document.head = new MockElement("head", document);
  document.body = new MockElement("body", document);
  document.documentElement.appendChild(document.head);
  document.documentElement.appendChild(document.body);

  const observers = [];
  class MockMutationObserver {
    constructor(callback) { this.callback = callback; this.disconnected = false; observers.push(this); }
    observe() {}
    disconnect() { this.disconnected = true; }
  }
  let nextTimer = 0;
  const timerIds = new Set();
  const matchMedia = () => ({ matches: false, addEventListener() {}, removeEventListener() {} });
  const window = { matchMedia, navigation: null };
  const context = vm.createContext({
    window,
    document,
    location: { protocol: "app:", pathname: "/", search: "" },
    MutationObserver: MockMutationObserver,
    setTimeout: () => { const id = ++nextTimer; timerIds.add(id); return id; },
    clearTimeout: (id) => timerIds.delete(id),
    setInterval: () => { const id = ++nextTimer; timerIds.add(id); return id; },
    clearInterval: (id) => timerIds.delete(id),
    performance: { now: () => 1 },
    URL,
    Blob,
    Uint8Array,
    URLSearchParams,
    atob,
    console,
  });
  return {
    context,
    document,
    observers,
    activeObservers: () => observers.filter((observer) => !observer.disconnected).length,
    styleNodes: () => document.head.children.filter((child) => child.tagName === "STYLE"),
  };
}

function candidateTheme(id, imagePath, imageBytes) {
  return {
    theme: {
      id,
      name: id === nasaThemeId ? "NASA fixture" : "Foreign fixture",
      appearance: "light",
      art: {},
    },
    themePath: path.join(path.dirname(imagePath), "theme.json"),
    imagePath,
    imageBytes,
    safeCssRuntime: "@layer dreamskin-community { .fixture-safe { color: inherit; } }",
    fingerprint: `source-${id}`,
    sourceStamp: "fixture-stamp",
    safeCssStatus: "validated",
  };
}

async function stageRuntime() {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), "nasa-unified-runtime-"));
  const filesRoot = path.join(tempRoot, "files");
  const supportRoot = path.join(filesRoot, ".support");
  const engineRoot = path.join(supportRoot, "upstream", "Codex-Dream-Skin-1.5.20", "windows");
  const assetsTarget = path.join(engineRoot, "assets");
  const scriptsTarget = path.join(engineRoot, "scripts");
  const themeDirectory = path.join(filesRoot, "lone-star-theme");
  await fs.mkdir(assetsTarget, { recursive: true });
  await fs.mkdir(scriptsTarget, { recursive: true });
  await fs.mkdir(themeDirectory, { recursive: true });
  await fs.cp(rendererAssets, assetsTarget, { recursive: true });
  await fs.copyFile(sourceApi, path.join(scriptsTarget, "lone-star-runtime-api.mjs"));
  await fs.copyFile(path.join(upstream, "scripts", "image-metadata.mjs"), path.join(scriptsTarget, "image-metadata.mjs"));
  await fs.copyFile(sourceStyle, path.join(supportRoot, "lone-star-style.mjs"));
  const imagePath = path.join(themeDirectory, "background.png");
  await fs.copyFile(path.join(packageRoot, "background.png"), imagePath);
  await fs.writeFile(path.join(themeDirectory, "theme.json"), JSON.stringify({ id: nasaThemeId }));
  await fs.writeFile(path.join(themeDirectory, "theme.css"), "/* fixture source CSS */\n");
  await fs.writeFile(path.join(assetsTarget, "dream-skin.css"), "/* CORE_FIXTURE_STYLE */\n");
  const apiUrl = pathToFileURL(path.join(scriptsTarget, "lone-star-runtime-api.mjs")).href;
  const api = await import(`${apiUrl}?fixture=${Date.now()}`);
  return { tempRoot, api, imagePath, imageBytes: await fs.readFile(imagePath) };
}

const staged = await stageRuntime();
try {
  const styleModule = await import(pathToFileURL(sourceStyle).href + `?fixture=${Date.now()}`);
  const { nasaCss, nasaCssHash } = styleModule;
  assert.equal(createHash("sha256").update(nasaCss).digest("hex"), nasaCssHash);
  assert.equal(nasaCssHash, expectedOriginalStyleHash, "trusted NASA CSS changed from the previous adapter payload");

  const safeCss = "@layer dreamskin-community { .fixture-safe { color: inherit; } }";
  const nasa = await staged.api.loadPayload("unused", candidateTheme(nasaThemeId, staged.imagePath, staged.imageBytes));
  const unchangedNasaTheme = candidateTheme(nasaThemeId, staged.imagePath, staged.imageBytes);
  assert.notEqual(nasa.fingerprint, unchangedNasaTheme.fingerprint,
    "NASA payload fingerprint should include the unified details runtime identity");
  assert.equal(staged.api.themePayloadChanged(unchangedNasaTheme, nasa), false,
    "an unchanged raw theme fingerprint must not trigger repeated strong-audit payload updates");
  assert.equal(staged.api.themePayloadChanged({ ...unchangedNasaTheme, fingerprint: "changed-theme-source" }, nasa), true,
    "a changed source fingerprint must rebuild the renderer payload");
  assert.equal(staged.api.themePayloadChanged(unchangedNasaTheme, null), true,
    "a missing prior payload must be treated as changed");
  const expectedNasaCss = `/* CORE_FIXTURE_STYLE */\n\n${safeCss}\n\n${nasaCss}\n`;
  assert.ok(nasa.payload.includes(JSON.stringify(expectedNasaCss)), "NASA rules must be part of the one renderer stylesheet");
  assert.ok(nasa.payload.includes("nasaDetailsHash"));
  assert.match(nasa.payload, new RegExp(nasaCssHash));
  assert.ok(nasa.revision && nasa.styleRevision && nasa.fingerprint);

  const foreign = await staged.api.loadPayload("unused", candidateTheme("foreign-theme", staged.imagePath, staged.imageBytes));
  const expectedForeignCss = `/* CORE_FIXTURE_STYLE */\n\n${safeCss}\n`;
  assert.ok(foreign.payload.includes(JSON.stringify(expectedForeignCss)), "foreign theme core payload must keep its original CSS");
  assert.ok(!foreign.payload.includes(nasaCss), "foreign theme must not receive NASA rules");
  assert.notEqual(foreign.styleRevision, nasa.styleRevision, "the full CSS revision must distinguish NASA details");

  const renderer = makeRendererContext();
  const nasaResult = vm.runInContext(nasa.payload, renderer.context, { timeout: 5000 });
  assert.equal(nasaResult.installed, true, "the wrapper must preserve the engine payload return value");
  assert.equal(nasaResult.themeId, nasaThemeId);
  assert.equal(renderer.styleNodes().length, 1);
  const health = () => vm.runInContext(staged.api.nasaRuntimeHealthExpression(nasa), renderer.context, { timeout: 1000 });
  assert.equal(health().pass, true, "health expression should verify unified NASA payload state");
  assert.equal(renderer.context.window.__CODEX_DREAM_SKIN_STATE__.nasaDetailsHash, nasaCssHash);
  assert.equal(renderer.context.window.__CODEX_DREAM_SKIN_STATE__.nasaRuntimeVersion, 1);
  assert.ok(renderer.styleNodes()[0].textContent.includes("--ds-bg:#ECE5D6!important"), "the same style node must contain NASA rules");
  assert.ok(!renderer.document.getElementById("lone-star-local-adapter"));

  const firstState = renderer.context.window.__CODEX_DREAM_SKIN_STATE__;
  const firstObservers = [...renderer.observers];
  const secondNasaResult = vm.runInContext(nasa.payload, renderer.context, { timeout: 5000 });
  assert.equal(secondNasaResult.installed, true);
  assert.equal(firstState.rootObserver.disconnected, true);
  assert.equal(firstState.partObserver.disconnected, true);
  assert.equal(renderer.activeObservers(), 2, "re-execution should leave only one observer pair active");
  assert.equal(renderer.styleNodes().length, 1, "re-execution should reuse one unified style element");
  assert.ok(renderer.observers.length > firstObservers.length);
  assert.equal(health().pass, true);

  const foreignResult = vm.runInContext(foreign.payload, renderer.context, { timeout: 5000 });
  assert.equal(foreignResult.installed, true);
  assert.equal(foreignResult.themeId, "foreign-theme");
  assert.equal(renderer.styleNodes().length, 1);
  assert.ok(!renderer.styleNodes()[0].textContent.includes("--ds-bg:#ECE5D6!important"));
  assert.equal("nasaDetailsHash" in renderer.context.window.__CODEX_DREAM_SKIN_STATE__, false);
  assert.equal("nasaRuntimeVersion" in renderer.context.window.__CODEX_DREAM_SKIN_STATE__, false);
  assert.equal(health().pass, false, "NASA health must fail after switching to a foreign theme");
  assert.equal(renderer.activeObservers(), 2, "theme switch should clean old observers and leave one active pair");

  const foreignState = renderer.context.window.__CODEX_DREAM_SKIN_STATE__;
  assert.equal(foreignState.cleanup(), true, "unified renderer cleanup should succeed");
  assert.equal(renderer.styleNodes().length, 0, "cleanup should remove the unified style");
  assert.equal(renderer.activeObservers(), 0, "cleanup should pause all renderer observers");

  const manager = await fs.readFile(path.join(packageRoot, "manage-lone-star.ps1"), "utf8");
  assert.ok(!/Start-Process\s+-FilePath\s+\$node\.Path[\s\S]{0,200}['"]watch['"]/.test(manager), "manager must not start a separate adapter watch process");
  assert.ok(!manager.includes("adapter-watch.json"), "manager must not retain the old adapter watcher record");
  assert.ok(manager.includes("$node.Path $adapter health"), "manager should run a one-shot health check");
  assert.ok(manager.includes("unifiedWatcherPid=$state.injectorPid"), "manager should report the single unified engine watcher");
  const adapter = await fs.readFile(path.join(packageRoot, "lone-star-adapter.mjs"), "utf8");
  assert.ok(adapter.includes("nasaRuntimeHealthExpression(loaded)"), "health command should use the unified payload expression");

  console.log(`Unified runtime tests passed under ${nodeVersion}.`);
} finally {
  const fixtureRelative = path.relative(os.tmpdir(), staged.tempRoot);
  assert.ok(!path.isAbsolute(fixtureRelative) && fixtureRelative !== ".." &&
    !fixtureRelative.startsWith(`..${path.sep}`) && path.basename(staged.tempRoot).startsWith("nasa-unified-runtime-"),
  `refusing to remove fixture outside its owned temporary directory: ${staged.tempRoot}`);
  await fs.rm(staged.tempRoot, { recursive: true, force: true });
}

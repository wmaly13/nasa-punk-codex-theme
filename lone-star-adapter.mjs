import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { listAppTargets, connectTarget, probeSession, connectBrowserIdentityAnchor, capture, loadPayload, nasaRuntimeHealthExpression } from './upstream/Codex-Dream-Skin-1.5.20/windows/scripts/lone-star-runtime-api.mjs';

import { nasaCssHash } from './lone-star-style.mjs';

const here = path.dirname(fileURLToPath(import.meta.url));
const mode = process.argv[2] || 'inspect';
if (!['inspect','apply','health'].includes(mode)) throw new Error('Unsupported adapter mode.');
// A slow or unavailable renderer must not leave the daily launch waiting forever.
if (mode==='health') setTimeout(()=>{console.error('Runtime health check timed out.');process.exit(2);},10000).unref();
const state = JSON.parse(await fs.readFile(path.join(process.env.LOCALAPPDATA,'CodexDreamSkin','state.json'),'utf8'));
if (!Number.isInteger(state.port) || state.port<1024 || state.port>65535 || !/^[A-Za-z0-9._-]{1,200}$/.test(state.browserId||'')) throw new Error('Invalid saved Dream Skin identity.');

// Fixed trusted local styles; no downloaded executable theme payload.
// This adapter is separate from the original installer-managed engine.
const inspection = `(() => {
  const state=window.__CODEX_DREAM_SKIN_STATE__;
  if(state?.themeId!=='nasa-punk-device-light') return {skipped:true};
  const read=n=>{if(!n)return null;const s=getComputedStyle(n),r=n.getBoundingClientRect();return {tag:n.tagName,cls:String(n.className).slice(0,1024),rect:{x:r.x,y:r.y,width:r.width,height:r.height},background:s.backgroundColor,image:s.backgroundImage,color:s.color,opacity:s.opacity,position:s.position,z:s.zIndex,padding:s.padding,border:s.border,borderWidths:[s.borderTopWidth,s.borderRightWidth,s.borderBottomWidth,s.borderLeftWidth],outline:s.outline,shadow:s.boxShadow,radius:s.borderRadius,blur:s.backdropFilter,font:s.fontFamily,fontSize:s.fontSize,weight:s.fontWeight};};
  const pick=sel=>[...document.querySelectorAll(sel)].find(n=>!n.closest('[data-app-shell-active-page="false"]')&&n.getBoundingClientRect().width>0)||document.querySelector(sel);
  const c=pick('[data-ds-part="composer"]'),h=pick('[data-ds-part="header"]'),side=pick('[data-ds-part="sidebar"]');
  const pseudo=name=>{if(!side)return null;const s=getComputedStyle(side,name);return {content:s.content,top:s.top,left:s.left,right:s.right,width:s.width,height:s.height,z:s.zIndex,opacity:s.opacity,pointerEvents:s.pointerEvents,background:s.backgroundImage};};
  const parents=[];for(let n=c,i=0;n&&i<6;n=n.parentElement,i++)parents.push(read(n));
  return {themeId:state.themeId,revision:state.revision,visibility:document.visibilityState,viewport:{width:innerWidth,height:innerHeight},
    surfaceAlpha:getComputedStyle(document.documentElement).getPropertyValue('--ds-user-surface-alpha'),
    header:read(h),headerButtons:[...(h?.querySelectorAll('button')||[])].slice(0,8).map(read),
    headerText:[...(h?.querySelectorAll('[class~="text-default"],[class~="text-foreground"]')||[])].slice(0,12).map(read),
    sidebar:read(side),band:pseudo('::before'),orbit:pseudo('::after'),composerParents:parents,
    sidebarEdgeNodes:side?[...document.elementsFromPoint(side.getBoundingClientRect().right+16,innerHeight/2)].slice(0,6).map(n=>({...read(n),role:n.getAttribute('role'),label:n.getAttribute('aria-label'),testId:n.getAttribute('data-testid'),markup:n.outerHTML.slice(0,1500)})):[],
    titlebarPieces:[...document.querySelectorAll('[data-app-shell-titlebar], [data-app-shell-header-slot], [data-app-shell-main-titlebar], [data-app-shell-header-edge-scroll]')].filter(n=>n.getBoundingClientRect().width>0).map(n=>({...read(n),slot:n.getAttribute('data-app-shell-header-slot'),after:{content:getComputedStyle(n,'::after').content,background:getComputedStyle(n,'::after').backgroundColor}})),
    brandButtons:[...(side?.querySelectorAll('button')||[])].filter(n=>/^ChatGPT/.test(n.innerText.trim())||/切换模式/.test(n.getAttribute('aria-label')||'')).map(n=>({...read(n),label:n.getAttribute('aria-label'),contentMarkup:n.innerHTML.slice(0,3000),after:{content:getComputedStyle(n,'::after').content,color:getComputedStyle(n,'::after').color,left:getComputedStyle(n,'::after').left,top:getComputedStyle(n,'::after').top,bottom:getComputedStyle(n,'::after').bottom,width:getComputedStyle(n,'::after').width,height:getComputedStyle(n,'::after').height,image:getComputedStyle(n,'::after').backgroundImage,pointerEvents:getComputedStyle(n,'::after').pointerEvents}})),
    composerButtons:[...(c?.querySelectorAll('button')||[])].filter(n=>/发送|停止|send|stop|voice|语音|对话/i.test(n.getAttribute('aria-label')||'')||n.classList.contains('bg-primary-solid')||n.classList.contains('bg-token-foreground')).map(n=>({...read(n),label:n.getAttribute('aria-label'),testId:n.getAttribute('data-testid'),variant:n.getAttribute('data-variant'),svg:n.querySelector('svg')?.outerHTML,svgColor:n.querySelector('svg')?getComputedStyle(n.querySelector('svg')).color:null})),
    footers:[...document.querySelectorAll('[data-thread-scroll-footer="true"]')].map(n=>({self:read(n),children:[...n.children].map(read)})),
    nativeFades:[...document.querySelectorAll('.pointer-events-none.sticky > [aria-hidden="true"].pointer-events-none.absolute')].map(read),
    assistant:read(document.querySelector('[data-local-conversation-final-assistant="true"][data-ds-part="message"]')),
    adapter:state.nasaDetailsHash===${JSON.stringify(nasaCssHash)},unifiedRuntime:state.nasaRuntimeVersion===1,
    activity:[...document.querySelectorAll('[data-response-annotation-conversation][data-response-annotation-target],[data-local-conversation-item-target-ids]')].filter(n=>n.getBoundingClientRect().width>0).map(read),
    menus:[...document.querySelectorAll('[role="menu"],[role="dialog"],[role="listbox"]')].filter(n=>n.getBoundingClientRect().width>0).map(read),
    closeCandidates:[...document.querySelectorAll('button,[role="button"]')].filter(n=>n.getBoundingClientRect().width>0 && /关闭|close|dismiss/i.test([n.getAttribute('aria-label'),n.getAttribute('title'),n.getAttribute('data-testid')].join(' '))).map(n=>({...read(n),label:n.getAttribute('aria-label'),title:n.getAttribute('title'),testId:n.getAttribute('data-testid'),markup:n.outerHTML.slice(0,3000),parentMarkup:n.parentElement.outerHTML.slice(0,4500),grandparentTag:n.parentElement.parentElement.tagName,grandparentClass:String(n.parentElement.parentElement.className),grandparentAttrs:[...n.parentElement.parentElement.attributes].map(a=>[a.name,a.value])})),
    popupLayers:[...document.querySelectorAll('[data-radix-popper-content-wrapper],[role="menu"],[role="dialog"],[role="listbox"],[data-ds-part="dialog"],[data-slot="popover-content"],[data-slot="dropdown-menu-content"]')].filter(n=>n.getBoundingClientRect().width>0).map(n=>({...read(n),role:n.getAttribute('role'),part:n.getAttribute('data-ds-part'),slot:n.getAttribute('data-slot'),popper:n.hasAttribute('data-radix-popper-content-wrapper'),parent:read(n.parentElement),paintedChildren:[...n.children].filter(x=>x.getBoundingClientRect().width>0&&[getComputedStyle(x).borderTopWidth,getComputedStyle(x).outlineWidth].some(v=>parseFloat(v)>0)).map(read)})),
    paintedGradients:[...document.querySelectorAll('body *')].filter(n=>!n.closest('[data-app-shell-active-page="false"]')&&n.getBoundingClientRect().width>0&&getComputedStyle(n).backgroundImage.includes('gradient(')).slice(0,40).map(read),
    overflow:{x:document.documentElement.scrollWidth>innerWidth+1,y:document.documentElement.scrollHeight>innerHeight+1}};
})()`;

async function run() {
  const loaded = await loadPayload(path.join(process.env.LOCALAPPDATA,'CodexDreamSkin','active-theme'));
  if (loaded.theme.id !== 'nasa-punk-device-light') throw new Error('Active theme is not NASA.');
  const results=[];
  for(const target of await listAppTargets(state.port,state.browserId)) {
    let session;
    try {
      session=await connectTarget(target,state.port);
      const probe=await probeSession(session);
      if(!probe?.codex||probe.excludedPetSurface)continue;
      if(mode==='apply') await session.evaluate(loaded.payload);
      const value=await session.evaluate(mode==='inspect'?inspection:nasaRuntimeHealthExpression(loaded));
      results.push({targetId:target.id,...value});
      if(mode==='inspect') {
        try {
          await session.send('DOM.enable');
          await session.send('CSS.enable');
          const doc=await session.send('DOM.getDocument',{depth:0});
          const node=await session.send('DOM.querySelector',{nodeId:doc.root.nodeId,selector:'[data-ds-part="composer"]'});
          if(node.nodeId) results.at(-1).platformFonts=(await session.send('CSS.getPlatformFontsForNode',{nodeId:node.nodeId})).fonts;
        } catch(error) { results.at(-1).fontInspectionError=error.message; }
      }
      if(process.argv.includes('--screenshot')) {
        try { await capture(session,path.join(here,`client-${mode}-${target.id}.png`)); }
        catch(error) { results.at(-1).screenshotError=error.message; }
      }
    } finally {session?.close();}
  }
  return results;
}

const anchor=await connectBrowserIdentityAnchor(state.port,state.browserId);
try {
  const results=await run();
  const pass=results.length>0&&(mode==='inspect'||results.every(item=>item.pass===true));
  const report={mode,pass,browserId:state.browserId,unifiedRuntime:true,results};
  if(mode!=='health') await fs.writeFile(path.join(here,`adapter-${mode}.json`),JSON.stringify(report,null,2));
  console.log(JSON.stringify(report));
  if(!pass)process.exitCode=2;
} finally {anchor.close();}

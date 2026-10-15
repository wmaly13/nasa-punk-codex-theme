// Fixed local NASA styles. Included atomically in the engine payload.
import fs from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const backgroundArt = (await fs.readFile(path.join(here,"..","lone-star-theme","background.png"))).toString("base64");
export const nasaCss = `@layer dreamskin-community {
/* Project palette; pin opaque surfaces rather than the engine's glass defaults. */
html[data-dream-skin="active"] {
  --ds-bg:#ECE5D6!important; --ds-bg-rgb:236 229 214!important;
  --ds-panel:#E4DDCE!important; --ds-panel-rgb:228 221 206!important;
  --ds-panel-2:#F2ECDF!important; --ds-panel-2-rgb:242 236 223!important;
  --ds-text:#20262A!important; --ds-text-rgb:32 38 42!important;
  --ds-muted:#51565A!important; --ds-muted-rgb:81 86 90!important;
  --ds-accent:#D63A2C!important; --ds-accent-rgb:214 58 44!important;
  --ds-secondary:#4C5A68!important; --ds-secondary-rgb:76 90 104!important;
  --ds-line:#B9B1A0!important; --ds-on-accent:#ECE5D6!important;
  --ds-upload-bg-alpha:1!important; --ds-upload-panel-alpha:1!important;
  --ds-upload-panel-alt-alpha:1!important; --ds-user-surface-alpha:1!important;
  --ds-user-panel-alpha:1!important;
  --ds-hero-scrim:none!important; --ds-task-shade:none!important;
  --ds-task-fade:none!important; --ds-task-full-veil:none!important;
  --font-sans:Helvetica,Arial,"Microsoft YaHei",sans-serif!important;
  --font-mono:Consolas,"Liberation Mono",monospace!important;
  --dream-skin-art:url("data:image/png;base64,${backgroundArt}")!important;
}
html[data-dream-skin="active"] :is([data-ds-part="root"],[data-ds-part="sidebar"],[data-ds-part="main"],[data-ds-part="thread"],[data-ds-part="message"],[data-ds-part="header"],[data-ds-part="composer"],[data-ds-part="dialog"]) {
  font-family:Helvetica,Arial,"Microsoft YaHei",sans-serif!important;
  text-shadow:none!important;
}
html[data-dream-skin="active"] :is([data-ds-part="sidebar"],aside.app-shell-left-panel) {
  background:#E4DDCE!important; background-image:none!important;
  box-shadow:none!important; backdrop-filter:none!important;
}
html[data-dream-skin="active"] [data-ds-part="sidebar"] :is([aria-current="page"],[class~="bg-token-list-hover-background"]) {
  background:#DAD2C2!important; border:1px solid #B9B1A0!important;
  border-radius:2px!important; box-shadow:inset 3px 0 #A8432F!important;
}
html[data-dream-skin="active"] :is([data-ds-part="main"],main.main-surface,main[data-app-shell-main-surface]) {
  background-color:transparent!important; background-image:none!important;
  box-shadow:none!important; border-radius:0!important;
}
html[data-dream-skin="active"] body {
  font-family:Helvetica,Arial,"Microsoft YaHei",sans-serif!important;
  background-color:#ECE5D6!important;
  background-image:var(--dream-skin-art)!important;
  background-size:cover!important; background-repeat:no-repeat!important;
  background-position:78% 45%!important; background-attachment:scroll!important;
}
html[data-dream-skin="active"] [data-app-shell-titlebar="true"]::after {
  background:#E4DDCE!important; background-image:none!important;
}
/* The native start slot is 6px wide. Leave it clear so the graphite header
   continues underneath, rather than painting a separate sidebar-colored cell. */
html[data-dream-skin="active"] [data-app-shell-titlebar="true"] [data-app-shell-header-slot="start"] {
  background:transparent!important; background-image:none!important;
}
html[data-dream-skin="active"] [data-ds-part="sidebar"] button[aria-label^="切换模式"] {
  font-size:20px!important; font-weight:600!important;
}
/* The workspace ID band follows the native mode button's content box.
   SVG preserveAspectRatio=none fills its exact box instead of letterboxing. */
html[data-dream-skin="active"] [data-ds-part="sidebar"] button[aria-label^="切换模式"]::after {
  content:""!important; position:absolute!important; left:6px!important; right:auto!important;
  top:auto!important; bottom:-10px!important; width:calc(100% - 12px)!important; height:4px!important;
  background:center/100% 100% no-repeat url("data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%20164%204%22%20preserveAspectRatio%3D%22none%22%3E%3Cpath%20fill%3D%22%234C5A68%22%20d%3D%22M0%200h41v4H0z%22%2F%3E%3Cpath%20fill%3D%22%237A7F4E%22%20d%3D%22M41%200h41v4H41z%22%2F%3E%3Cpath%20fill%3D%22%23D2A85E%22%20d%3D%22M82%200h41v4H82z%22%2F%3E%3Cpath%20fill%3D%22%23A8432F%22%20d%3D%22M123%200h41v4h-41z%22%2F%3E%3C%2Fsvg%3E")!important;
  border:0!important; box-shadow:none!important; opacity:1!important; filter:none!important;
  pointer-events:none!important;
}
html[data-dream-skin="active"] [data-app-shell-frame][data-app-shell-sidebar-open="false"] [data-ds-part="sidebar"] button[aria-label^="切换模式"]::after {
  content:none!important;
}
html[data-dream-skin="active"] [data-ds-part="header"] {
  background:#20262A!important; background-image:none!important;
  --ds-text:#ECE5D6!important; --ds-text-rgb:236 229 214!important;
  --ds-muted:#D1CCBF!important; --ds-muted-rgb:209 204 191!important;
  --color-token-foreground:#ECE5D6!important; --color-token-text-secondary:#D1CCBF!important;
  --color-token-muted-foreground:#D1CCBF!important;
  --color-text:#ECE5D6!important; --color-text-emphasis:#ECE5D6!important;
  --color-text-default:#ECE5D6!important; --color-text-primary:#ECE5D6!important;
  --color-text-secondary:#D1CCBF!important; --color-text-tertiary:#D1CCBF!important;
  --color-text-toolbar-action:#ECE5D6!important; --color-token-text-primary:#ECE5D6!important;
  color:#ECE5D6!important; text-shadow:none!important;
}
html[data-dream-skin="active"] :is([role="menu"],[role="dialog"],[role="listbox"],[data-ds-part="dialog"],[data-slot="popover-content"],[data-slot="dropdown-menu-content"]) {
  --ds-text:#20262A!important; --ds-text-rgb:32 38 42!important;
  --ds-muted:#51565A!important; --ds-muted-rgb:81 86 90!important;
  --color-token-foreground:#20262A!important; --color-token-text-secondary:#51565A!important;
  --color-token-muted-foreground:#51565A!important; --color-token-text-primary:#20262A!important;
  --color-text:#20262A!important; --color-text-primary:#20262A!important;
  --color-text-default:#20262A!important; --color-text-emphasis:#20262A!important;
  --color-text-secondary:#51565A!important; --color-text-tertiary:#51565A!important;
  --color-text-toolbar-action:#20262A!important;
  background:#F2ECDF!important; background-image:none!important; color:#20262A!important;
  border:1px solid #B9B1A0!important; border-radius:2px!important;
  backdrop-filter:none!important; box-shadow:none!important;
}
/* Positioning shells are not panel faces. Painting both shell and face made
   a double 1px frame on the workspace and model menus. Preserve native placement. */
html[data-dream-skin="active"] [data-radix-popper-content-wrapper]:not(:is([role="menu"],[role="dialog"],[role="listbox"])),
html[data-dream-skin="active"] :is([data-ds-part="dialog"],[data-slot="popover-content"],[data-slot="dropdown-menu-content"]):not(:is([role="menu"],[role="dialog"],[role="listbox"])):has(> :is([role="menu"],[role="dialog"],[role="listbox"],[data-slot="popover-content"],[data-slot="dropdown-menu-content"])) {
  background:transparent!important; background-image:none!important;
  border:0!important; box-shadow:none!important; backdrop-filter:none!important;
}
html[data-dream-skin="active"] [role="menu"] :is(button,[role="menuitem"]) {
  color:#20262A!important;
}
/* Streaming activity and expanded tool cards had the engine's diagonal glass gradients. */
html[data-dream-skin="active"] .thread-scroll-container :is([data-response-annotation-conversation][data-response-annotation-target],[data-local-conversation-item-target-ids]) {
  background:#F2ECDF!important; background-image:none!important;
  border:1px solid #B9B1A0!important; border-radius:2px!important;
  box-shadow:none!important; backdrop-filter:none!important;
  color:#20262A!important;
}
html[data-dream-skin="active"] .thread-scroll-container [data-local-conversation-final-assistant] [data-response-annotation-conversation][data-response-annotation-target] {
  background:transparent!important; background-image:none!important; border:0!important;
}
html[data-dream-skin="active"] [data-local-conversation-final-assistant="true"][data-ds-part="message"] {
  padding:0!important; border:0!important;
}
html[data-dream-skin="active"] [data-ds-part="thread"] :is(.markdown,.prose) a {
  color:#A8432F!important;
}
html[data-dream-skin="active"] :is(.markdown,.prose) :is(code,pre,kbd,samp),
html[data-dream-skin="active"] [class~="font-mono"] {
  font-family:Consolas,"Liberation Mono",monospace!important;
}
html[data-dream-skin="active"] [data-ds-part="composer"] {
  background:#F2ECDF!important; background-image:none!important;
  border:1px solid #B9B1A0!important; border-top:2px solid #20262A!important;
  border-radius:2px!important; box-shadow:none!important; backdrop-filter:none!important;
}
/* Preserve the application's send/stop SVG and hit area. Only restyle its keycap.
   Ordinary send is graphite; stopping an active run is the red critical action. */
html[data-dream-skin="active"] [data-ds-part="composer"] :is(button[class~="bg-composer-primary"],button[class~="bg-primary-solid"],button[class~="bg-token-foreground"],button[aria-label*="发送"],button[aria-label*="send" i]) {
  background:#20262A!important; background-image:none!important; color:#ECE5D6!important;
  --color-text-composer-primary:#ECE5D6!important;
  border:1px solid #20262A!important; border-radius:2px!important; box-shadow:none!important;
}
html[data-dream-skin="active"] [data-ds-part="composer"] :is(button[aria-label="停止"],button[aria-label*="stop" i]) {
  background:#D63A2C!important; background-image:none!important; color:#ECE5D6!important;
  --color-text-composer-primary:#ECE5D6!important;
  border:1px solid #A8432F!important; border-radius:2px!important; box-shadow:none!important;
}
html[data-dream-skin="active"] [data-ds-part="composer"] :is(button[class~="bg-composer-primary"],button[class~="bg-primary-solid"],button[class~="bg-token-foreground"],button[aria-label*="发送"],button[aria-label*="send" i],button[aria-label="停止"],button[aria-label*="stop" i]) :is(svg,path) {
  color:#ECE5D6!important; opacity:1!important;
}
/* Solid pointer-inert lower paint preserves native footer geometry and covers the bottom inset. */
html[data-dream-skin="active"] [data-thread-scroll-footer="true"] > [aria-hidden="true"].pointer-events-none.absolute {
  background:#ECE5D6!important; background-image:none!important; opacity:1!important;
}
html[data-dream-skin="active"] .pointer-events-none.sticky > [aria-hidden="true"].pointer-events-none.absolute.bg-gradient-to-t.from-surface {
  background:none!important; background-image:none!important; opacity:1!important;
}
html[data-dream-skin="active"] [data-ds-part="sidebar"]::before {
  content:none!important;
}
html[data-dream-skin="active"] [data-app-shell-frame][data-app-shell-sidebar-open="false"] [data-ds-part="sidebar"]::before,
html[data-dream-skin="active"] [data-app-shell-frame][data-app-shell-sidebar-open="false"] [data-ds-part="sidebar"]::after { content:none!important; }
html[data-dream-skin="active"] [data-ds-part="sidebar"]::after {
  content:""!important; position:absolute!important; top:41px!important; right:20px!important;
  left:auto!important; bottom:auto!important; width:16px!important; height:16px!important;
  background:center/contain no-repeat url("data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20viewBox%3D%220%200%2024%2024%22%20fill%3D%22none%22%20stroke%3D%22%234C5A68%22%20stroke-width%3D%221.5%22%20stroke-linecap%3D%22round%22%20stroke-linejoin%3D%22round%22%3E%3Ccircle%20cx%3D%2212%22%20cy%3D%2212%22%20r%3D%223%22%2F%3E%3Ccircle%20cx%3D%2219%22%20cy%3D%225%22%20r%3D%222%22%2F%3E%3Ccircle%20cx%3D%225%22%20cy%3D%2219%22%20r%3D%222%22%2F%3E%3Cpath%20d%3D%22M7.4%203.1a10%2010%200%200%201%2013.5%2013.5M16.6%2020.9A10%2010%200%200%201%203.1%207.4%22%2F%3E%3C%2Fsvg%3E")!important;
  z-index:1!important; opacity:1!important; filter:none!important;
  box-shadow:none!important; border:0!important; pointer-events:none!important;
}
/* A viewer-close key must be visually distinct from the native window caption X.
   Scope to the semantic viewer button inside its dialog; preserve size/hitbox. */
html[data-dream-skin="active"] [role="dialog"] button:is([aria-label="关闭查看器"],[aria-label="Close viewer"]) {
  background:#20262A!important; background-image:none!important;
  color:#ECE5D6!important; border:1px solid #20262A!important;
  border-radius:3px!important; box-shadow:none!important;
  backdrop-filter:none!important; opacity:1!important;
}
html[data-dream-skin="active"] [role="dialog"] button:is([aria-label="关闭查看器"],[aria-label="Close viewer"]) :is(svg,path) {
  color:#ECE5D6!important; opacity:1!important;
}
html[data-dream-skin="active"] [role="dialog"] button:is([aria-label="关闭查看器"],[aria-label="Close viewer"]):hover {
  background:#4C5A68!important; border-color:#4C5A68!important;
}
html[data-dream-skin="active"] [role="dialog"] button:is([aria-label="关闭查看器"],[aria-label="Close viewer"]):focus-visible {
  outline:2px solid #A8432F!important; outline-offset:2px!important;
}
/* Opaque viewer controls need no image filtering. Preserve native transitions. */
html[data-dream-skin="active"] [role="dialog"]:has([data-testid="viewer-header"]) {
  --image-viewer-transparent-backdrop-filter:none!important;
}
html[data-dream-skin="active"] [role="dialog"] [data-testid="viewer-header"] :is(button,[role="group"]) {
  backdrop-filter:none!important; -webkit-backdrop-filter:none!important;
}
}
@layer properties {
html[data-dream-skin="active"] [data-ds-part="composer"] { backdrop-filter:none!important; }
}`;

export const nasaCssHash=createHash('sha256').update(nasaCss).digest('hex');

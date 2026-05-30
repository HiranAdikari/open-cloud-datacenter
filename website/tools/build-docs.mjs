import { writeFileSync, readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';

const SRC = '/Users/hiranadikari/ocd-controlplane/docs';
const OUT = '/Users/hiranadikari/ocd-site/website/docs';

const DOCS = [
  { slug: 'local-dev',     file: 'local-dev.md',           title: 'Local development',    group: 'Getting started' },
  { slug: 'architecture',  file: 'dc-api-architecture.md', title: 'Architecture',         group: 'Concepts' },
  { slug: 'rbac',          file: 'rbac.md',                title: 'RBAC & roles',         group: 'Security' },
  { slug: 'ops-bootstrap', file: 'ops-bootstrap.md',       title: 'Operations bootstrap', group: 'Operations' },
];

const md = (file) => {
  const raw = readFileSync(`${SRC}/${file}`, 'utf8').replace(/^---\n[\s\S]*?\n---\n/, '');
  return execSync('npx --yes marked', { input: raw, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
};

const GH = '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 .5C5.7.5.5 5.7.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.3.8-.6v-2c-3.2.7-3.9-1.4-3.9-1.4-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.7 1.3 3.4 1 .1-.8.4-1.3.7-1.6-2.6-.3-5.3-1.3-5.3-5.8 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.1 0 0 1-.3 3.3 1.2a11.5 11.5 0 0 1 6 0C17.3 4.7 18.3 5 18.3 5c.6 1.6.2 2.8.1 3.1.8.8 1.2 1.8 1.2 3.1 0 4.5-2.7 5.5-5.3 5.8.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6 4.6-1.5 7.9-5.8 7.9-10.9C23.5 5.7 18.3.5 12 .5Z"/></svg>';
const CHEV = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="m6 9 6 6 6-6"/></svg>';

function sidebar(active) {
  const groups = {};
  for (const d of DOCS) (groups[d.group] ||= []).push(d);
  let html = '';
  for (const [g, items] of Object.entries(groups)) {
    html += `<div class="docnav__group"><div class="docnav__title" data-collapse>${g} ${CHEV}</div><div class="docnav__list">`;
    for (const d of items) html += `<a href="${d.slug}.html"${d.slug === active ? ' class="is-active"' : ''}>${d.title}</a>`;
    html += `</div></div>`;
  }
  return html;
}

function page({ title, active, body }) {
  return `<!DOCTYPE html>
<html lang="en" data-theme="light" data-density="comfortable">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${title} — OpenStrato Docs</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;600&display=swap" rel="stylesheet">
<link rel="stylesheet" href="../styles/tokens.css">
<link rel="stylesheet" href="../styles/main.css">
<link rel="stylesheet" href="../styles/docs.css">
</head>
<body>
<a class="skip-link" href="#doc">Skip to content</a>
<header class="nav">
  <div class="nav__inner container" style="max-width:1440px">
    <button class="icon-btn docnav-toggle" id="docnavToggle" aria-label="Toggle navigation"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M3 6h18M3 12h18M3 18h18"/></svg></button>
    <a class="brand" href="../index.html"><svg class="brand__mark" viewBox="0 0 32 32" fill="none"><rect x="1.5" y="1.5" width="29" height="29" rx="8" fill="var(--accent)"/><rect x="8" y="9" width="16" height="3" rx="1.5" fill="#fff"/><rect x="8" y="14.5" width="16" height="3" rx="1.5" fill="#fff" opacity="0.7"/><rect x="8" y="20" width="10" height="3" rx="1.5" fill="#fff" opacity="0.45"/></svg><span class="brand__name"><b>Open</b><span>Strato</span></span></a>
    <nav class="nav__links" aria-label="Primary">
      <a class="nav__link" href="index.html" style="color:var(--ink)">Docs</a>
      <a class="nav__link" href="../api/index.html">API</a>
      <a class="nav__link" href="cli/index.html">CLI</a>
    </nav>
    <div class="nav__spacer"></div>
    <div class="nav__actions">
      <button class="icon-btn theme-toggle" data-action="toggle-theme" aria-label="Toggle theme"><svg class="icon-sun" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></svg><svg class="icon-moon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z"/></svg></button>
      <a class="icon-btn" href="#" aria-label="GitHub">${GH}</a>
    </div>
  </div>
</header>
<div class="docshell">
  <aside class="docnav" id="docnav">${sidebar(active)}</aside>
  <main class="doccontent" id="doc"><article class="prose" style="max-width:860px">${body}</article></main>
</div>
<script src="../scripts/site.js"></script>
<script>document.getElementById("docnavToggle").addEventListener("click",function(){document.getElementById("docnav").classList.toggle("is-open");});</script>
</body>
</html>`;
}

const NOTE = (file) =>
  `<div class="callout callout--note"><svg class="callout__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M12 16v-4M12 8h.01" stroke-linecap="round"/></svg><div class="callout__body">Imported verbatim from the project's <code>docs/${file}</code>. Some pages still carry upstream "Sovereign Cloud / Asgardeo" wording, pending a generic pass.</div></div>`;

for (const d of DOCS) {
  writeFileSync(`${OUT}/${d.slug}.html`, page({ title: d.title, active: d.slug, body: NOTE(d.file) + md(d.file) }));
  console.log('wrote', `${d.slug}.html`);
}

const cards = DOCS.map(
  (d) => `<a class="doccard" href="${d.slug}.html"><span class="doccard__group">${d.group}</span><span class="doccard__title">${d.title} →</span></a>`
).join('');
const indexBody = `<h1>Documentation</h1>
<p class="lead">Guides and references for running and using the control plane. Pages below are generated from the project's real documentation.</p>
${NOTE('*.md')}
<style>.doc-cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:var(--sp-4);margin-top:var(--sp-5)}.doccard{display:flex;flex-direction:column;gap:6px;padding:var(--sp-5);border:1px solid var(--border);border-radius:var(--r-lg);text-decoration:none;background:var(--surface);transition:border-color .12s,background .12s}.doccard:hover{border-color:var(--accent-border);background:var(--accent-soft)}.doccard__group{font-size:var(--t-xs);text-transform:uppercase;letter-spacing:.06em;color:var(--secondary);font-weight:600}.doccard__title{font-weight:600;color:var(--ink)}</style>
<div class="doc-cards">${cards}</div>`;
writeFileSync(`${OUT}/index.html`, page({ title: 'Documentation', active: null, body: indexBody }));
console.log('wrote index.html');

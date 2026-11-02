(() => {
  'use strict';
  const data = JSON.parse(document.getElementById('wiki-data').textContent);
  const pages = new Map(data.pages.map((p) => [p.id, p]));
  const main = document.getElementById('content');
  const railNav = document.getElementById('rail-nav');
  const sidebar = document.getElementById('sidebar');
  const scrim = document.getElementById('scrim');
  const menuBtn = document.getElementById('menu-btn');
  let current = null;
  let spy = null;

  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { if (v == null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { /* storage unavailable */ } },
  };

  // ---------------------------------------------------------------- routing
  function parseHash() {
    let h = location.hash.slice(1);
    try { h = decodeURIComponent(h); } catch (e) { /* keep raw */ }
    if (!h) return { page: 'home', section: null };
    const cut = h.indexOf('--');
    const page = cut >= 0 ? h.slice(0, cut) : h;
    if (!pages.has(page)) return { page: 'home', section: null };
    return { page, section: cut >= 0 ? h : null };
  }

  function route() {
    const { page, section } = parseHash();
    if (page !== current) {
      const tpl = document.getElementById('tpl-' + page);
      if (!tpl) return;
      main.replaceChildren(tpl.content.cloneNode(true));
      current = page;
      const meta = pages.get(page);
      document.title = page === 'home' ? tpl.dataset.title : `${meta.title} · ${data.site} DeepWiki`;
      enhance(main);
      buildRail();
      markNav();
      if (!section) window.scrollTo(0, 0);
    }
    if (section) {
      const el = document.getElementById(section);
      if (el) {
        el.scrollIntoView({ block: 'start' });
        flash(el);
      }
    }
    closeNav();
  }

  function flash(el) {
    el.classList.remove('flash');
    void el.offsetWidth;
    el.classList.add('flash');
  }

  function markNav() {
    sidebar.querySelectorAll('a[data-page]').forEach((a) => {
      const on = a.dataset.page === current;
      a.classList.toggle('active', on);
      if (on) a.setAttribute('aria-current', 'page'); else a.removeAttribute('aria-current');
    });
    const active = sidebar.querySelector('a.active');
    if (active && active.scrollIntoView) {
      const r = active.getBoundingClientRect();
      const s = sidebar.getBoundingClientRect();
      if (r.top < s.top || r.bottom > s.bottom) active.scrollIntoView({ block: 'center' });
    }
  }

  // ---------------------------------------------------------------- outline rail + scrollspy
  function buildRail() {
    railNav.replaceChildren();
    if (spy) { spy.disconnect(); spy = null; }
    const heads = [...main.querySelectorAll('.prose h2[id], .prose h3[id]')];
    document.getElementById('rail').hidden = heads.length < 2;
    const links = new Map();
    for (const h of heads) {
      const a = document.createElement('a');
      a.href = '#' + h.id;
      a.className = h.tagName === 'H3' ? 'lv3' : 'lv2';
      const clone = h.cloneNode(true);
      clone.querySelectorAll('.h-anchor').forEach((n) => n.remove());
      a.textContent = clone.textContent.trim();
      railNav.appendChild(a);
      links.set(h.id, a);
    }
    if (!('IntersectionObserver' in window) || !heads.length) return;
    const visible = new Set();
    spy = new IntersectionObserver((entries) => {
      for (const e of entries) { if (e.isIntersecting) visible.add(e.target.id); else visible.delete(e.target.id); }
      let pick = null;
      for (const h of heads) { if (visible.has(h.id)) { pick = h.id; break; } }
      if (!pick) {
        for (const h of heads) { if (h.getBoundingClientRect().top < 120) pick = h.id; }
      }
      links.forEach((a, id) => a.classList.toggle('active', id === pick));
    }, { rootMargin: '-64px 0px -70% 0px', threshold: [0, 1] });
    heads.forEach((h) => spy.observe(h));
  }

  // ---------------------------------------------------------------- page enhancements
  function enhance(root) {
    root.querySelectorAll('.code .copy').forEach((btn) => {
      btn.addEventListener('click', () => {
        const code = btn.closest('.code').querySelector('pre code');
        const text = code.innerText;
        const done = () => { btn.textContent = 'コピーした'; setTimeout(() => { btn.textContent = 'コピー'; }, 1400); };
        const fallback = () => {
          const range = document.createRange();
          range.selectNodeContents(code);
          const sel = window.getSelection();
          sel.removeAllRanges();
          sel.addRange(range);
          btn.textContent = '選択した';
          setTimeout(() => { btn.textContent = 'コピー'; }, 1400);
        };
        try {
          if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fallback);
          else fallback();
        } catch (e) { fallback(); }
      });
    });
    root.querySelectorAll('.diagram .zoom').forEach((btn) => {
      btn.addEventListener('click', () => openZoom(btn.closest('.diagram')));
    });
  }

  const zoomLayer = document.getElementById('zoom-layer');
  const zoomBody = document.getElementById('zoom-body');
  let zoomReturn = null;
  function openZoom(fig) {
    const shown = [...fig.querySelectorAll('.mm')].find((n) => getComputedStyle(n).display !== 'none');
    const svg = shown && shown.querySelector('svg');
    if (!svg) return;
    const copy = svg.cloneNode(true);
    const vb = (svg.getAttribute('viewBox') || '').split(/\s+/).map(Number);
    copy.removeAttribute('style');
    if (vb.length === 4 && vb[2] > 0) {
      const scale = Math.max(1.25, Math.min(2.2, (window.innerWidth - 48) / vb[2]));
      copy.setAttribute('width', String(Math.round(vb[2] * scale)));
      copy.setAttribute('height', String(Math.round(vb[3] * scale)));
    }
    zoomBody.replaceChildren(copy);
    zoomReturn = document.activeElement;
    zoomLayer.hidden = false;
    document.getElementById('zoom-close').focus();
  }
  function closeZoom() {
    if (zoomLayer.hidden) return;
    zoomLayer.hidden = true;
    zoomBody.replaceChildren();
    if (zoomReturn && zoomReturn.focus) zoomReturn.focus();
  }
  document.getElementById('zoom-close').addEventListener('click', closeZoom);

  // ---------------------------------------------------------------- mobile drawer
  function openNav() {
    document.body.classList.add('nav-open');
    scrim.hidden = false;
    menuBtn.setAttribute('aria-expanded', 'true');
  }
  function closeNav() {
    if (!document.body.classList.contains('nav-open')) return;
    document.body.classList.remove('nav-open');
    scrim.hidden = true;
    menuBtn.setAttribute('aria-expanded', 'false');
  }
  menuBtn.addEventListener('click', () => (document.body.classList.contains('nav-open') ? closeNav() : openNav()));
  scrim.addEventListener('click', closeNav);

  // ---------------------------------------------------------------- theme toggle (standalone build only)
  const themeBtn = document.getElementById('theme-btn');
  if (themeBtn) {
    const order = ['system', 'light', 'dark'];
    const label = { system: 'システム', light: 'ライト', dark: 'ダーク' };
    const apply = (mode) => {
      if (mode === 'system') document.documentElement.removeAttribute('data-theme');
      else document.documentElement.setAttribute('data-theme', mode);
      themeBtn.title = '配色: ' + label[mode];
      themeBtn.setAttribute('aria-label', '配色を切り替える（現在: ' + label[mode] + '）');
    };
    let mode = store.get('deepwiki-theme') || 'system';
    if (!order.includes(mode)) mode = 'system';
    apply(mode);
    themeBtn.addEventListener('click', () => {
      mode = order[(order.indexOf(mode) + 1) % order.length];
      store.set('deepwiki-theme', mode === 'system' ? null : mode);
      apply(mode);
    });
  }

  // ---------------------------------------------------------------- search
  const q = document.getElementById('q');
  const results = document.getElementById('results');
  const norm = (s) => s.normalize('NFKC').toLowerCase();
  const index = [];
  for (const p of data.search) {
    for (const s of p.s) {
      index.push({ page: p.p, title: p.t, group: p.g, id: s.i, head: s.h, text: s.x, nt: norm(p.t), nh: norm(s.h), nx: norm(s.x) });
    }
  }
  const escHTML = (s) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  function mark(text, terms) {
    let out = escHTML(text);
    for (const t of terms) {
      if (!t) continue;
      const re = new RegExp(escHTML(t).replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'gi');
      out = out.replace(re, (m) => `<mark>${m}</mark>`);
    }
    return out;
  }
  function snippet(item, terms) {
    const nx = item.nx;
    let at = -1;
    for (const t of terms) { const i = nx.indexOf(t); if (i >= 0 && (at < 0 || i < at)) at = i; }
    if (at < 0) return item.text.slice(0, 110);
    const start = Math.max(0, at - 40);
    return (start > 0 ? '…' : '') + item.text.slice(start, start + 140) + (start + 140 < item.text.length ? '…' : '');
  }
  let sel = -1;
  function search() {
    const raw = q.value.trim();
    if (!raw) { results.hidden = true; return; }
    const terms = norm(raw).split(/\s+/).filter(Boolean);
    const hits = [];
    for (const it of index) {
      let score = 0;
      let ok = true;
      for (const t of terms) {
        const inT = it.nt.includes(t), inH = it.nh.includes(t), inX = it.nx.includes(t);
        if (!inT && !inH && !inX) { ok = false; break; }
        score += (inT ? 6 : 0) + (inH ? 4 : 0) + (inX ? 1 : 0);
      }
      if (ok) hits.push({ it, score });
    }
    hits.sort((a, b) => b.score - a.score);
    const top = hits.slice(0, 30);
    results.replaceChildren();
    if (!top.length) {
      const d = document.createElement('div');
      d.className = 'r-empty';
      d.textContent = '「' + raw + '」に一致する節はない。';
      results.appendChild(d);
    }
    for (const { it } of top) {
      const a = document.createElement('a');
      a.href = '#' + it.id;
      a.innerHTML = `<span class="r-title">${mark(it.title, terms)}${it.head ? ` <span class="r-sec">› ${mark(it.head, terms)}</span>` : ''}</span>`
        + `<span class="r-snip">${mark(snippet(it, terms), terms)}</span>`;
      a.addEventListener('click', () => { results.hidden = true; q.blur(); });
      results.appendChild(a);
    }
    sel = -1;
    results.hidden = false;
  }
  q.addEventListener('input', search);
  q.addEventListener('focus', () => { if (q.value.trim()) search(); });
  q.addEventListener('keydown', (e) => {
    const items = [...results.querySelectorAll('a')];
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (!items.length) return;
      e.preventDefault();
      sel = (sel + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length;
      items.forEach((a, i) => a.classList.toggle('active', i === sel));
      items[sel].scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      const a = items[sel >= 0 ? sel : 0];
      if (a) { e.preventDefault(); location.hash = a.getAttribute('href').slice(1); results.hidden = true; q.blur(); }
    } else if (e.key === 'Escape') {
      results.hidden = true; q.blur();
    }
  });
  document.addEventListener('click', (e) => { if (!e.target.closest('.search')) results.hidden = true; });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') { closeZoom(); closeNav(); }
    if (e.key === '/' && !e.ctrlKey && !e.metaKey && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName)) {
      e.preventDefault();
      q.focus();
      q.select();
    }
  });

  window.addEventListener('hashchange', route);
  route();
})();

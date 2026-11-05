/* Origin Design System — perilaku komponen. Vanilla JS tanpa dependensi, satu listener per jenis event.
   Aman dipakai di HTML biasa, Laravel Blade, maupun Svelte. Pasang sekali: <script src="/origin.js" defer></script>
   Sprite eksternal: <html data-origin-sprite="/origin-sprite.svg"> */
(() => {
  if (window.OriginUI) return;
  const root = document.documentElement;
  const KEY = "origin-theme";
  const NS = "http://www.w3.org/2000/svg";
  const sprite = () => root.dataset.originSprite || "";
  const icon = (name) => `<svg class="icon" aria-hidden="true"><use href="${sprite()}#i-${name}"/></svg>`;
  const reduceMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const store = {
    get() { try { return localStorage.getItem(KEY); } catch (e) { return null; } },
    set(v) { try { v === "system" ? localStorage.removeItem(KEY) : localStorage.setItem(KEY, v); } catch (e) {} },
  };

  /* ---------- Tema ---------- */
  function setTheme(choice) {
    if (choice === "light" || choice === "dark") root.dataset.theme = choice;
    else { delete root.dataset.theme; choice = "system"; }
    store.set(choice);
    document.querySelectorAll("[data-theme-choice]").forEach((b) => b.setAttribute("aria-pressed", String(b.dataset.themeChoice === choice)));
  }

  /* ---------- Tab ---------- */
  function selectTab(tab, focus) {
    const list = tab.closest('[role="tablist"]');
    if (!list) return;
    list.querySelectorAll('[role="tab"]').forEach((t) => {
      const on = t === tab;
      t.setAttribute("aria-selected", String(on));
      t.tabIndex = on ? 0 : -1;
      const panel = document.getElementById(t.getAttribute("aria-controls"));
      if (panel) panel.hidden = !on;
    });
    if (focus) tab.focus();
    tab.dispatchEvent(new CustomEvent("origin:tab", { bubbles: true }));
  }

  /* ---------- Drawer ---------- */
  let lastFocus = null;
  function backdropFor(drawer) {
    let b = document.querySelector(`.drawer-backdrop[data-for="${drawer.id}"]`);
    if (!b) {
      b = document.createElement("button");
      b.type = "button";
      b.className = "drawer-backdrop";
      b.dataset.for = drawer.id;
      b.tabIndex = -1;
      b.setAttribute("aria-label", "Tutup panel");
      drawer.before(b);
    }
    return b;
  }
  function openDrawer(drawer) {
    lastFocus = document.activeElement;
    drawer.dataset.open = "true";
    backdropFor(drawer).dataset.open = "true";
    drawer.setAttribute("aria-hidden", "false");
    const first = drawer.querySelector("button, a, input, select, textarea");
    setTimeout(() => (first || drawer).focus(), 50);
  }
  function closeDrawer(drawer) {
    drawer.dataset.open = "false";
    backdropFor(drawer).dataset.open = "false";
    drawer.setAttribute("aria-hidden", "true");
    if (lastFocus) lastFocus.focus();
  }

  /* ---------- Menu dropdown (<details class="menu">) ----------
     Panel dipasang position: fixed agar tidak terpotong tabel atau wadah yang bisa digulir. */
  function place(trigger, panel, alignStart) {
    panel.style.position = "fixed";
    panel.style.right = "auto";
    panel.style.top = "0px";
    panel.style.left = "0px";
    const r = trigger.getBoundingClientRect();
    const w = panel.offsetWidth;
    const h = panel.offsetHeight;
    let top = r.bottom + 6;
    if (top + h > innerHeight - 8 && r.top - h - 6 > 8) top = r.top - h - 6;
    let left = alignStart ? r.left : r.right - w;
    left = Math.max(8, Math.min(left, innerWidth - w - 8));
    const off = panel.getBoundingClientRect();
    panel.style.left = `${left - off.left}px`;
    panel.style.top = `${top - off.top}px`;
  }
  function placeMenu(d) {
    const panel = d.querySelector(".menu__panel");
    const trigger = d.querySelector("summary");
    if (panel && trigger) place(trigger, panel, d.classList.contains("menu--start"));
  }
  function closeMenus(except) {
    document.querySelectorAll("details.menu[open]").forEach((d) => { if (d !== except) d.open = false; });
  }
  document.addEventListener("toggle", (e) => {
    const d = e.target;
    if (!(d instanceof HTMLDetailsElement) || !d.classList.contains("menu")) return;
    if (d.open) { closeMenus(d); placeMenu(d); }
    else { const p = d.querySelector(".menu__panel"); if (p) p.removeAttribute("style"); }
  }, true);
  window.addEventListener("scroll", (e) => {
    if (e.target instanceof Element && e.target.closest(".menu__panel")) return;
    closeMenus();
  }, { passive: true, capture: true });
  window.addEventListener("resize", () => closeMenus());

  /* ---------- Panel navigasi (navbar dan sidebar) ----------
     Di ponsel panel tampil position: fixed; saat itu latar gelap dipasang dan halaman dikunci. */
  function setPanel(id, open) {
    const target = document.getElementById(id);
    if (target) target.dataset.open = String(open);
    document.querySelectorAll(`[data-menu-toggle][aria-controls="${id}"]`).forEach((b) => b.setAttribute("aria-expanded", String(open)));
    if (!target) return;
    const floating = getComputedStyle(target).position === "fixed";
    let bd = document.querySelector(`.offcanvas-backdrop[data-for="${id}"]`);
    if (floating && !bd) {
      bd = document.createElement("button");
      bd.type = "button";
      bd.className = "offcanvas-backdrop";
      bd.dataset.for = id;
      bd.tabIndex = -1;
      bd.setAttribute("aria-label", "Tutup menu");
      target.after(bd);
    }
    if (bd) bd.dataset.open = String(open && floating);
    document.documentElement.style.overflow = open && floating ? "hidden" : "";
    if (open && floating) setTimeout(() => target.querySelector("a, button, input")?.focus(), 60);
  }

  /* ---------- Sidebar ringkas (desktop) ---------- */
  const SIDEBAR_KEY = "origin-sidebar";
  function setCollapsed(app, collapsed, remember = true) {
    app.dataset.collapsed = String(collapsed);
    app.querySelectorAll("[data-sidebar-toggle]").forEach((b) => {
      b.setAttribute("aria-expanded", String(!collapsed));
      b.setAttribute("aria-label", collapsed ? "Lebarkan menu" : "Ciutkan menu");
    });
    if (remember) { try { localStorage.setItem(SIDEBAR_KEY, collapsed ? "collapsed" : "expanded"); } catch (e) {} }
  }

  /* ---------- Toast ---------- */
  function region(position = "bottom-right") {
    let r = document.querySelector(`.toast-region[data-position="${position}"]`);
    if (!r) {
      r = document.createElement("div");
      r.className = "toast-region";
      r.dataset.position = position;
      r.setAttribute("role", "status");
      r.setAttribute("aria-live", "polite");
      document.body.append(r);
    }
    return r;
  }
  const toastIcon = { info: "info", success: "circle-check", warning: "triangle-alert", danger: "circle-alert" };
  function dismissToast(el) {
    if (!el || el.dataset.leaving) return;
    el.dataset.leaving = "true";
    el.addEventListener("animationend", () => el.remove(), { once: true });
    setTimeout(() => el.remove(), 400);
  }
  function toast({ title = "", text = "", type = "info", position = "bottom-right", timeout = 4500 } = {}) {
    const el = document.createElement("div");
    el.className = `toast toast--${type}`;
    el.innerHTML = `<span class="toast__icon">${icon(toastIcon[type] || "info")}</span><div><div class="toast__title"></div><div class="toast__text"></div></div><button type="button" class="close-btn" data-dismiss aria-label="Tutup">${icon("x")}</button>`;
    el.querySelector(".toast__title").textContent = title;
    el.querySelector(".toast__text").textContent = text;
    if (!text) el.querySelector(".toast__text").remove();
    const r = region(position);
    position.startsWith("top") ? r.prepend(el) : r.append(el);
    if (timeout) setTimeout(() => dismissToast(el), timeout);
    return el;
  }

  /* ---------- Salin ---------- */
  function copyText(text, btn) {
    const done = (ok) => {
      if (!btn || btn.dataset.copyBusy) return;
      btn.dataset.copyBusy = "1";
      const old = btn.innerHTML;
      btn.innerHTML = `${icon(ok ? "check" : "x")}${ok ? "Tersalin" : "Gagal, salin manual"}`;
      setTimeout(() => { btn.innerHTML = old; delete btn.dataset.copyBusy; }, 1600);
    };
    /* Cadangan untuk browser atau iframe yang menolak Clipboard API */
    const legacy = () => {
      const ta = document.createElement("textarea");
      ta.value = text; ta.setAttribute("readonly", ""); ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.append(ta); ta.select();
      let ok = false;
      try { ok = document.execCommand("copy"); } catch (e) { ok = false; }
      ta.remove(); done(ok); return ok;
    };
    if (navigator.clipboard?.writeText) return navigator.clipboard.writeText(text).then(() => { done(true); return true; }, () => legacy());
    return Promise.resolve(legacy());
  }

  /* ---------- Grafik (SVG, tanpa library) ---------- */
  const nf = new Intl.NumberFormat("id-ID");
  const fmt = (v) => nf.format(v);
  const compact = (v) => (Math.abs(v) >= 1e6 ? `${nf.format(+(v / 1e6).toFixed(1))} jt` : Math.abs(v) >= 1e4 ? `${nf.format(+(v / 1e3).toFixed(1))} rb` : nf.format(v));
  const svgEl = (tag, attrs = {}, parent) => {
    const e = document.createElementNS(NS, tag);
    for (const k in attrs) e.setAttribute(k, attrs[k]);
    if (parent) parent.append(e);
    return e;
  };
  function niceScale(max, ticks = 4) {
    if (!(max > 0)) return { max: ticks, step: 1 };
    const raw = max / ticks;
    const mag = 10 ** Math.floor(Math.log10(raw));
    const n = raw / mag;
    const step = (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * mag;
    return { max: step * Math.ceil(max / step - 1e-9), step };
  }
  const roundTop = (x, y, w, h, r) => {
    r = Math.min(r, h, w / 2);
    return `M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z`;
  };
  const arc = (cx, cy, r0, r1, a0, a1) => {
    const p = (r, a) => [cx + r * Math.sin(a), cy - r * Math.cos(a)];
    const large = a1 - a0 > Math.PI ? 1 : 0;
    const [x0, y0] = p(r1, a0), [x1, y1] = p(r1, a1), [x2, y2] = p(r0, a1), [x3, y3] = p(r0, a0);
    return `M${x0},${y0}A${r1},${r1} 0 ${large} 1 ${x1},${y1}L${x2},${y2}A${r0},${r0} 0 ${large} 0 ${x3},${y3}Z`;
  };

  function chart(rootEl, cfg) {
    if (!rootEl) return;
    cfg = cfg || JSON.parse(rootEl.dataset.chart || "{}");
    if (rootEl._origin) rootEl._origin.disconnect();
    rootEl.classList.add("chart");
    const type = cfg.type || "line";
    const series = (cfg.series || []).slice(0, 4);
    if ((cfg.series || []).length > 4) console.warn("OriginUI.chart: maksimal 4 seri. Gabungkan sisanya menjadi 'Lainnya' atau pecah jadi beberapa grafik.");
    const labels = cfg.labels || [];
    const unit = cfg.unit || "";
    const title = cfg.title || rootEl.querySelector(".chart__title")?.textContent || "Grafik";

    let head = rootEl.querySelector(".chart__head");
    if (!head) { head = document.createElement("div"); head.className = "chart__head"; rootEl.prepend(head); }
    head.querySelector(".chart__legend")?.remove();
    rootEl.querySelectorAll(".chart__plot, .chart__data").forEach((n) => n.remove());

    const total = type === "donut" ? series[0].values.reduce((a, b) => a + b, 0) : 0;
    if (type === "donut" || series.length > 1) {
      const legend = document.createElement("ul");
      legend.className = "chart__legend";
      const items = type === "donut" ? labels.map((l, i) => ({ name: l, i, v: series[0].values[i] })) : series.map((s, i) => ({ name: s.name, i }));
      items.forEach(({ name, i, v }) => {
        const li = document.createElement("li");
        const key = document.createElement("span");
        key.className = `chart__key${type === "line" ? "" : " chart__key--box"}`;
        key.style.setProperty("--key", `var(--chart-${i + 1})`);
        li.append(key, document.createTextNode(name));
        if (v !== undefined) { const s = document.createElement("strong"); s.textContent = `${fmt(v)} (${Math.round((v / total) * 100)}%)`; li.append(" ", s); }
        legend.append(li);
      });
      head.append(legend);
    }

    const plot = document.createElement("div");
    plot.className = "chart__plot";
    const tip = document.createElement("div");
    tip.className = "chart__tip";
    tip.setAttribute("aria-hidden", "true");
    plot.append(tip);
    rootEl.append(plot);

    const data = document.createElement("details");
    data.className = "chart__data";
    data.innerHTML = `<summary>${icon("chevron-down")}Lihat data</summary><div class="table-wrap"><table class="table"><thead><tr></tr></thead><tbody></tbody></table></div>`;
    const hr = data.querySelector("thead tr");
    const th0 = document.createElement("th"); th0.scope = "col"; th0.textContent = cfg.labelName || "Label"; hr.append(th0);
    series.forEach((s) => { const th = document.createElement("th"); th.scope = "col"; th.className = "num"; th.textContent = s.name || "Nilai"; hr.append(th); });
    const tb = data.querySelector("tbody");
    labels.forEach((l, i) => {
      const tr = document.createElement("tr");
      const td = document.createElement("td"); td.textContent = l; tr.append(td);
      series.forEach((s) => { const c = document.createElement("td"); c.className = "num"; c.textContent = fmt(s.values[i]) + unit; tr.append(c); });
      tb.append(tr);
    });
    rootEl.append(data);

    function showTip(x, y, heading, rows) {
      tip.replaceChildren();
      if (heading) { const t = document.createElement("div"); t.className = "chart__tip-title"; t.textContent = heading; tip.append(t); }
      rows.forEach(({ i, name, value }) => {
        const r = document.createElement("div"); r.className = "chart__tip-row";
        const k = document.createElement("span"); k.className = `chart__key${type === "line" ? "" : " chart__key--box"}`; k.style.setProperty("--key", `var(--chart-${i + 1})`);
        const v = document.createElement("strong"); v.textContent = value;
        const n = document.createElement("span"); n.textContent = name;
        r.append(k, v, n); tip.append(r);
      });
      tip.dataset.show = "";
      const pw = plot.clientWidth, tw = tip.offsetWidth, th = tip.offsetHeight;
      let left = x + 14; if (left + tw > pw) left = x - tw - 14; left = Math.max(0, left);
      let top = y - th / 2; top = Math.max(0, Math.min(top, plot.clientHeight - th));
      tip.style.left = `${left}px`; tip.style.top = `${top}px`;
    }
    const hideTip = () => { delete tip.dataset.show; };

    function draw() {
      plot.querySelector("svg")?.remove();
      const W = Math.max(240, plot.clientWidth);
      const H = cfg.height || (type === "donut" ? 220 : 240);
      plot.style.setProperty("--chart-h", `${H}px`);
      const svg = svgEl("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", tabindex: "0", "aria-label": `${title}. Tekan panah kiri dan kanan untuk membaca nilai.` });
      plot.prepend(svg);

      if (type === "donut") {
        const size = Math.min(H, W);
        const cx = W / 2, cy = H / 2, r1 = size / 2 - 4, r0 = r1 * 0.68;
        let a = 0;
        const segs = series[0].values.map((v, i) => {
          const a1 = a + (v / total) * Math.PI * 2;
          const p = svgEl("path", { d: arc(cx, cy, r0, r1, a, Math.max(a, a1 - 0.0001)), class: `c-seg s${i + 1}` }, svg);
          const mid = (a + a1) / 2; a = a1;
          return { p, i, v, mid };
        });
        svgEl("text", { x: cx, y: cy + 4, "text-anchor": "middle", class: "c-center-value" }, svg).textContent = fmt(total);
        svgEl("text", { x: cx, y: cy + 24, "text-anchor": "middle", class: "c-center-label" }, svg).textContent = cfg.centerLabel || "Total";
        const focusSeg = (k) => {
          segs.forEach((s) => s.p.classList.toggle("is-dim", s.i !== k));
          const s = segs[k];
          const x = cx + (r1 + 6) * Math.sin(s.mid), y = cy - (r1 + 6) * Math.cos(s.mid);
          showTip(Math.min(x, W - 10), y, labels[k], [{ i: k, name: `${Math.round((s.v / total) * 100)}% dari total`, value: fmt(s.v) + unit }]);
        };
        const clear = () => { segs.forEach((s) => s.p.classList.remove("is-dim")); hideTip(); };
        segs.forEach((s) => { s.p.addEventListener("pointerenter", () => focusSeg(s.i)); s.p.addEventListener("pointerleave", clear); });
        let k = -1;
        svg.addEventListener("keydown", (e) => {
          if (!["ArrowLeft", "ArrowRight"].includes(e.key)) return;
          e.preventDefault(); k = (k + (e.key === "ArrowRight" ? 1 : -1) + segs.length) % segs.length; focusSeg(k);
        });
        svg.addEventListener("blur", clear);
        return;
      }

      const n = labels.length;
      const maxV = Math.max(...series.flatMap((s) => s.values), 0);
      const sc = niceScale(cfg.max || maxV, 4);
      const ticks = []; for (let v = 0; v <= sc.max + 1e-9; v += sc.step) ticks.push(v);
      const padL = Math.max(...ticks.map((t) => compact(t).length)) * 6.6 + 12;
      const padR = 12, padT = 10, padB = 28;
      const iw = W - padL - padR, ih = H - padT - padB;
      const y = (v) => padT + ih - (v / sc.max) * ih;
      const band = iw / n;
      const x = type === "bar" ? (i) => padL + band * i + band / 2 : (i) => padL + (n === 1 ? iw / 2 : (iw * i) / (n - 1));

      ticks.forEach((t) => {
        svgEl("line", { x1: padL, x2: W - padR, y1: y(t), y2: y(t), class: t === 0 ? "c-base" : "c-grid" }, svg);
        svgEl("text", { x: padL - 8, y: y(t) + 4, "text-anchor": "end", class: "c-tick" }, svg).textContent = compact(t);
      });
      const every = Math.max(1, Math.ceil(n / Math.max(1, Math.floor(iw / 64))));
      labels.forEach((l, i) => {
        if (i % every !== 0) return;
        const anchor = type === "line" && i === 0 ? "start" : type === "line" && i === n - 1 ? "end" : "middle";
        svgEl("text", { x: x(i), y: H - 8, "text-anchor": anchor, class: "c-tick" }, svg).textContent = l;
      });

      let marks = [];
      if (type === "bar") {
        const k = series.length, gap = 2;
        const bw = Math.min(24, (band * 0.72 - gap * (k - 1)) / k);
        const gw = bw * k + gap * (k - 1);
        labels.forEach((_, i) => {
          const group = [];
          series.forEach((s, j) => {
            const v = s.values[i], h = Math.max(0, y(0) - y(v));
            const bx = x(i) - gw / 2 + j * (bw + gap);
            group.push(svgEl("path", { d: roundTop(bx, y(v), bw, h, 4), class: `c-bar s${j + 1}` }, svg));
          });
          marks.push(group);
        });
      } else {
        series.forEach((s, j) => {
          const pts = s.values.map((v, i) => [x(i), y(v)]);
          const line = pts.map((p, i) => `${i ? "L" : "M"}${p[0]},${p[1]}`).join("");
          if (cfg.area !== false && (series.length === 1 || cfg.area === true)) svgEl("path", { d: `${line}L${pts[pts.length - 1][0]},${y(0)}L${pts[0][0]},${y(0)}Z`, class: `c-area s${j + 1}` }, svg);
          svgEl("path", { d: line, class: `c-line s${j + 1}` }, svg);
          const last = pts[pts.length - 1];
          svgEl("circle", { cx: last[0], cy: last[1], r: 4, class: `c-dot s${j + 1}` }, svg);
        });
      }

      const cross = svgEl("line", { y1: padT, y2: padT + ih, class: "c-cross", visibility: "hidden" }, svg);
      const hover = series.map((_, j) => svgEl("circle", { r: 4, class: `c-dot s${j + 1}`, visibility: "hidden" }, svg));
      const hit = svgEl("rect", { x: padL, y: padT, width: iw, height: ih + padB - 6, fill: "transparent" }, svg);
      let cur = -1;
      const focusAt = (i) => {
        cur = i;
        const rows = series.map((s, j) => ({ i: j, name: s.name || "", value: fmt(s.values[i]) + unit }));
        if (type === "bar") {
          marks.forEach((g, gi) => g.forEach((m) => m.classList.toggle("is-dim", gi !== i)));
          showTip(x(i) + Math.min(24, band / 2), y(Math.max(...series.map((s) => s.values[i]))), labels[i], rows);
        } else {
          cross.setAttribute("x1", x(i)); cross.setAttribute("x2", x(i)); cross.setAttribute("visibility", "visible");
          series.forEach((s, j) => { hover[j].setAttribute("cx", x(i)); hover[j].setAttribute("cy", y(s.values[i])); hover[j].setAttribute("visibility", "visible"); });
          showTip(x(i), y(Math.max(...series.map((s) => s.values[i]))), labels[i], rows);
        }
      };
      const clear = () => {
        cur = -1; hideTip(); cross.setAttribute("visibility", "hidden");
        hover.forEach((h) => h.setAttribute("visibility", "hidden"));
        marks.forEach((g) => g.forEach((m) => m.classList.remove("is-dim")));
      };
      hit.addEventListener("pointermove", (e) => {
        const r = svg.getBoundingClientRect();
        const px = ((e.clientX - r.left) / r.width) * W - padL;
        const i = type === "bar" ? Math.floor(px / band) : Math.round((px / iw) * (n - 1));
        const c = Math.max(0, Math.min(n - 1, i));
        if (c !== cur) focusAt(c);
      });
      hit.addEventListener("pointerleave", clear);
      svg.addEventListener("keydown", (e) => {
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
        e.preventDefault();
        const nxt = e.key === "Home" ? 0 : e.key === "End" ? n - 1 : cur < 0 ? (e.key === "ArrowRight" ? 0 : n - 1) : Math.max(0, Math.min(n - 1, cur + (e.key === "ArrowRight" ? 1 : -1)));
        focusAt(nxt);
      });
      svg.addEventListener("blur", clear);
    }

    let lastW = 0;
    const ro = new ResizeObserver(() => {
      const w = plot.clientWidth;
      if (Math.abs(w - lastW) < 2) return;
      lastW = w;
      requestAnimationFrame(draw);
    });
    ro.observe(plot);
    rootEl._origin = ro;
    draw();
    return { redraw: draw };
  }

  function sparkline(svg) {
    const vals = (svg.dataset.spark || "").split(",").map(Number).filter((v) => !Number.isNaN(v));
    if (vals.length < 2) return;
    const W = svg.clientWidth || 120, H = svg.clientHeight || 36, pad = 5;
    const min = Math.min(...vals), max = Math.max(...vals), span = max - min || 1;
    const pts = vals.map((v, i) => [pad + ((W - pad * 2) * i) / (vals.length - 1), pad + (H - pad * 2) * (1 - (v - min) / span)]);
    svg.setAttribute("viewBox", `0 0 ${W} ${H}`);
    svg.replaceChildren();
    svgEl("path", { d: pts.map((p, i) => `${i ? "L" : "M"}${p[0]},${p[1]}`).join(""), class: "c-line" }, svg).style.cssText = "fill:none;stroke-width:2;stroke-linejoin:round;stroke-linecap:round";
    const l = pts[pts.length - 1];
    svgEl("circle", { cx: l[0], cy: l[1], r: 4, class: "c-dot" }, svg).style.cssText = "stroke:var(--bg-surface);stroke-width:2";
  }

  /* ---------- Klik ---------- */
  document.addEventListener("click", (e) => {
    const inMenuItem = e.target.closest(".menu__panel a, .menu__panel button");
    if (inMenuItem) { const d = inMenuItem.closest("details.menu"); if (d) d.open = false; }
    document.querySelectorAll("details.menu[open]").forEach((d) => { if (!d.contains(e.target)) d.open = false; });
    if (e.target instanceof HTMLDialogElement && e.target.classList.contains("dialog")) { e.target.close(); return; }

    const bdrop = e.target.closest(".offcanvas-backdrop");
    if (bdrop) { setPanel(bdrop.dataset.for, false); return; }
    const sideBtn = e.target.closest("[data-sidebar-toggle]");
    if (sideBtn) { const app = sideBtn.closest(".app"); if (app) setCollapsed(app, app.dataset.collapsed !== "true"); return; }

    const t = e.target.closest("[data-theme-choice],[data-menu-toggle],[role='tab'],[data-dialog-open],[data-dialog-close],[data-drawer-open],[data-drawer-close],.drawer-backdrop,[data-toast],[data-password-toggle],[data-dismiss],[data-copy],[data-copy-target]");
    if (!t) return;

    if (t.matches("[data-theme-choice]")) setTheme(t.dataset.themeChoice);
    else if (t.matches("[data-menu-toggle]")) {
      const id = t.getAttribute("aria-controls");
      const target = document.getElementById(id);
      const open = target ? target.dataset.open !== "true" : t.getAttribute("aria-expanded") !== "true";
      setPanel(id, open);
    } else if (t.matches("[role='tab']")) selectTab(t);
    else if (t.matches("[data-dialog-open]")) document.getElementById(t.dataset.dialogOpen)?.showModal();
    else if (t.matches("[data-dialog-close]")) t.closest("dialog")?.close(t.value || "");
    else if (t.matches("[data-drawer-open]")) { const d = document.getElementById(t.dataset.drawerOpen); if (d) openDrawer(d); }
    else if (t.matches("[data-drawer-close]")) { const d = t.closest(".drawer"); if (d) closeDrawer(d); }
    else if (t.matches(".drawer-backdrop")) { const d = document.getElementById(t.dataset.for); if (d) closeDrawer(d); }
    else if (t.matches("[data-toast]")) toast({ type: t.dataset.toast || "info", title: t.dataset.toastTitle || "", text: t.dataset.toastText || "", position: t.dataset.toastPosition || "bottom-right" });
    else if (t.matches("[data-password-toggle]")) {
      const input = t.closest(".input-group")?.querySelector("input");
      if (!input) return;
      const show = input.type === "password";
      input.type = show ? "text" : "password";
      t.setAttribute("aria-label", show ? "Sembunyikan kata sandi" : "Tampilkan kata sandi");
      t.setAttribute("aria-pressed", String(show));
      t.querySelector("use")?.setAttribute("href", `${sprite()}#i-${show ? "eye-off" : "eye"}`);
    } else if (t.matches("[data-dismiss]")) {
      const box = t.closest(".toast, .alert");
      if (box?.classList.contains("toast")) dismissToast(box); else box?.remove();
    } else if (t.matches("[data-copy]")) copyText(t.dataset.copy, t);
    else if (t.matches("[data-copy-target]")) {
      const src = document.querySelector(t.dataset.copyTarget);
      if (src) copyText("value" in src && src.tagName !== "BUTTON" ? src.value : src.textContent, t);
    }
  });

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape") {
      document.querySelectorAll('.drawer[data-open="true"]').forEach(closeDrawer);
      document.querySelectorAll("details.menu[open]").forEach((d) => { d.open = false; d.querySelector("summary")?.focus(); });
      document.querySelectorAll('.offcanvas-backdrop[data-open="true"]').forEach((b) => setPanel(b.dataset.for, false));
    }
    const tab = e.target.closest?.("[role='tab']");
    if (tab && ["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) {
      const tabs = [...tab.closest('[role="tablist"]').querySelectorAll('[role="tab"]')];
      let i = tabs.indexOf(tab);
      i = e.key === "Home" ? 0 : e.key === "End" ? tabs.length - 1 : (i + (e.key === "ArrowRight" ? 1 : -1) + tabs.length) % tabs.length;
      e.preventDefault();
      selectTab(tabs[i], true);
    }
  });

  const init = () => {
    setTheme(store.get() || root.dataset.theme || "system");
    document.querySelectorAll('[role="tablist"]').forEach((list) => {
      const sel = list.querySelector('[role="tab"][aria-selected="true"]') || list.querySelector('[role="tab"]');
      if (sel) selectTab(sel);
    });
    document.querySelectorAll(".drawer").forEach((d) => { if (d.dataset.open !== "true") d.setAttribute("aria-hidden", "true"); });
    let side = null;
    try { side = localStorage.getItem(SIDEBAR_KEY); } catch (e) {}
    document.querySelectorAll(".app").forEach((app) => setCollapsed(app, side === "collapsed" || (side === null && app.dataset.collapsed === "true"), false));
    document.querySelectorAll("[data-chart]").forEach((c) => { try { chart(c); } catch (err) { console.error("OriginUI.chart:", err); } });
    document.querySelectorAll("svg[data-spark]").forEach(sparkline);
    if (reduceMotion()) document.querySelectorAll(".loader-orbit svg, .loader-launch svg").forEach((s) => s.pauseAnimations?.());
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();

  window.OriginUI = { setTheme, toast, openDrawer, closeDrawer, selectTab, chart, sparkline, copy: copyText, place, setPanel, setCollapsed, icon };
})();

/* Origin Design System — komponen lanjutan: kalender, jam, slider, combobox, tag, tabel interaktif,
   form bertahap, pencarian cepat (Ctrl+K), dan lazy loading. Butuh origin.js dimuat lebih dulu. */
(() => {
  const UI = window.OriginUI;
  if (!UI || UI.extras) return;
  const icon = UI.icon;
  const MONTHS = ["Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli", "Agustus", "September", "Oktober", "November", "Desember"];
  const DAYS = ["Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu"];
  const DOW = ["Sen", "Sel", "Rab", "Kam", "Jum", "Sab", "Min"];
  const pad = (n) => String(n).padStart(2, "0");
  const iso = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const parse = (s) => { const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s || ""); return m ? new Date(+m[1], +m[2] - 1, +m[3]) : null; };
  const longDate = (d) => `${DAYS[d.getDay()]}, ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
  let openPicker = null;

  function closePicker(focusInput) {
    if (!openPicker) return;
    const { panel, input } = openPicker;
    panel.hidden = true;
    input.setAttribute("aria-expanded", "false");
    if (focusInput) input.focus();
    openPicker = null;
  }

  function hiddenFor(input) {
    let h = input.parentElement.querySelector('input[type="hidden"][data-picker-value]');
    if (!h) {
      h = document.createElement("input");
      h.type = "hidden";
      h.dataset.pickerValue = "";
      if (input.name) { h.name = input.name; input.removeAttribute("name"); }
      input.after(h);
    }
    return h;
  }

  /* ---------- Kalender ---------- */
  function datepicker(wrap) {
    if (wrap._picker) return;
    const input = wrap.querySelector("input:not([type=hidden])");
    const hidden = hiddenFor(input);
    const min = parse(wrap.dataset.min);
    let value = parse(input.value);
    let view = value ? new Date(value) : new Date();
    view.setDate(1);
    input.readOnly = true;
    input.setAttribute("aria-haspopup", "dialog");
    input.setAttribute("aria-expanded", "false");
    const sync = () => { hidden.value = value ? iso(value) : ""; input.value = value ? longDate(value) : ""; };
    sync();

    const panel = document.createElement("div");
    panel.className = "picker__panel";
    panel.hidden = true;
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", "Pilih tanggal");
    wrap.append(panel);

    function render(focusDate) {
      const today = new Date(); today.setHours(0, 0, 0, 0);
      const start = new Date(view); start.setDate(1 - ((view.getDay() + 6) % 7));
      const focus = focusDate || value || (view.getMonth() === today.getMonth() && view.getFullYear() === today.getFullYear() ? today : new Date(view));
      let html = `<div class="calendar"><div class="calendar__head"><button type="button" class="btn btn--ghost btn--icon btn--sm" data-cal="prev" aria-label="Bulan sebelumnya">${icon("chevron-left")}</button><span class="calendar__title" aria-live="polite">${MONTHS[view.getMonth()]} ${view.getFullYear()}</span><button type="button" class="btn btn--ghost btn--icon btn--sm" data-cal="next" aria-label="Bulan berikutnya">${icon("chevron-right")}</button></div><div class="calendar__grid" role="grid">`;
      html += DOW.map((d) => `<span class="calendar__dow" aria-hidden="true">${d}</span>`).join("");
      for (let i = 0; i < 42; i++) {
        const d = new Date(start); d.setDate(start.getDate() + i);
        const attrs = [];
        if (d.getMonth() !== view.getMonth()) attrs.push("data-outside");
        if (+d === +today) attrs.push("data-today");
        const sel = value && +d === +value;
        const disabled = min && d < min;
        html += `<button type="button" class="calendar__day" data-date="${iso(d)}" aria-selected="${sel}" aria-label="${longDate(d)}" tabindex="${+d === +focus ? 0 : -1}" ${attrs.join(" ")} ${disabled ? "disabled" : ""}>${d.getDate()}</button>`;
      }
      html += `</div><div class="calendar__foot"><button type="button" class="btn btn--ghost btn--sm" data-cal="today">Hari ini</button><button type="button" class="btn btn--ghost btn--sm" data-cal="clear">Hapus</button></div></div>`;
      panel.innerHTML = html;
    }
    function focusDay(d) {
      if (d.getMonth() !== view.getMonth() || d.getFullYear() !== view.getFullYear()) { view = new Date(d); view.setDate(1); render(d); }
      else render(d);
      panel.querySelector(`[data-date="${iso(d)}"]`)?.focus({ preventScroll: true });
    }
    function open() {
      if (openPicker && openPicker.panel === panel) return;
      closePicker();
      view = new Date(value || new Date()); view.setDate(1);
      render();
      panel.hidden = false;
      input.setAttribute("aria-expanded", "true");
      UI.place(wrap, panel, true);
      openPicker = { panel, input };
      (panel.querySelector('.calendar__day[tabindex="0"]') || panel.querySelector(".calendar__day")).focus({ preventScroll: true });
    }
    function choose(d) {
      value = d; sync(); closePicker(true);
      input.dispatchEvent(new Event("change", { bubbles: true }));
    }
    wrap.addEventListener("click", (e) => {
      if (panel.contains(e.target)) {
        const day = e.target.closest(".calendar__day");
        const act = e.target.closest("[data-cal]")?.dataset.cal;
        if (day && !day.disabled) choose(parse(day.dataset.date));
        else if (act === "prev" || act === "next") { view.setMonth(view.getMonth() + (act === "next" ? 1 : -1)); render(); panel.querySelector('.calendar__day[tabindex="0"]')?.focus({ preventScroll: true }); }
        else if (act === "today") { const t = new Date(); t.setHours(0, 0, 0, 0); choose(t); }
        else if (act === "clear") { value = null; sync(); closePicker(true); }
        return;
      }
      open();
    });
    input.addEventListener("keydown", (e) => { if (["Enter", " ", "ArrowDown"].includes(e.key)) { e.preventDefault(); open(); } });
    panel.addEventListener("keydown", (e) => {
      const day = e.target.closest(".calendar__day");
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closePicker(true); return; }
      if (!day) return;
      const d = parse(day.dataset.date);
      const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[e.key];
      if (step) { e.preventDefault(); d.setDate(d.getDate() + step); focusDay(d); }
      else if (e.key === "PageUp" || e.key === "PageDown") { e.preventDefault(); d.setMonth(d.getMonth() + (e.key === "PageDown" ? 1 : -1)); focusDay(d); }
      else if (e.key === "Home") { e.preventDefault(); d.setDate(d.getDate() - ((d.getDay() + 6) % 7)); focusDay(d); }
      else if (e.key === "End") { e.preventDefault(); d.setDate(d.getDate() + (6 - ((d.getDay() + 6) % 7))); focusDay(d); }
    });
    wrap._picker = { open };
  }

  /* ---------- Jam ---------- */
  function timepicker(wrap) {
    if (wrap._picker) return;
    const input = wrap.querySelector("input:not([type=hidden])");
    const hidden = hiddenFor(input);
    const step = +(wrap.dataset.step || 15);
    const [sh, sm] = (wrap.dataset.start || "06:00").split(":").map(Number);
    const [eh, em] = (wrap.dataset.end || "23:45").split(":").map(Number);
    const times = [];
    for (let m = sh * 60 + sm; m <= eh * 60 + em; m += step) times.push(`${pad(Math.floor(m / 60))}:${pad(m % 60)}`);
    let value = /^\d{2}:\d{2}$/.test(input.value) ? input.value : "";
    input.readOnly = true;
    input.setAttribute("aria-haspopup", "listbox");
    input.setAttribute("aria-expanded", "false");
    const sync = () => { hidden.value = value; input.value = value ? `${value} WIB` : ""; };
    sync();
    const panel = document.createElement("div");
    panel.className = "picker__panel";
    panel.hidden = true;
    panel.innerHTML = `<div class="timelist" role="listbox" aria-label="Pilih jam">${times.map((t) => `<button type="button" role="option" data-time="${t}" aria-selected="${t === value}" tabindex="-1">${t}</button>`).join("")}</div>`;
    wrap.append(panel);
    const items = () => [...panel.querySelectorAll("[data-time]")];
    function open() {
      if (openPicker && openPicker.panel === panel) return;
      closePicker();
      items().forEach((b) => b.setAttribute("aria-selected", String(b.dataset.time === value)));
      panel.hidden = false;
      input.setAttribute("aria-expanded", "true");
      UI.place(wrap, panel, true);
      openPicker = { panel, input };
      const cur = panel.querySelector('[aria-selected="true"]') || items()[0];
      const listEl = panel.querySelector(".timelist");
      listEl.scrollTop = cur.offsetTop - listEl.clientHeight / 2 + cur.offsetHeight / 2;
      cur.focus({ preventScroll: true });
    }
    wrap.addEventListener("click", (e) => {
      const b = e.target.closest("[data-time]");
      if (b) { value = b.dataset.time; sync(); closePicker(true); input.dispatchEvent(new Event("change", { bubbles: true })); return; }
      if (!panel.contains(e.target)) open();
    });
    input.addEventListener("keydown", (e) => { if (["Enter", " ", "ArrowDown"].includes(e.key)) { e.preventDefault(); open(); } });
    panel.addEventListener("keydown", (e) => {
      const list = items();
      const i = list.indexOf(document.activeElement);
      if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); closePicker(true); }
      else if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); const nx = list[Math.max(0, Math.min(list.length - 1, i + (e.key === "ArrowDown" ? 1 : -1)))]; nx.focus({ preventScroll: true }); nx.parentElement.scrollTop = nx.offsetTop - nx.parentElement.clientHeight / 2; }
    });
    wrap._picker = { open };
  }

  document.addEventListener("pointerdown", (e) => {
    if (openPicker && !openPicker.panel.contains(e.target) && !openPicker.panel.parentElement.contains(e.target)) closePicker();
  });
  window.addEventListener("resize", () => closePicker());
  window.addEventListener("scroll", (e) => { if (openPicker && !openPicker.panel.contains(e.target)) closePicker(); }, { passive: true, capture: true });

  /* ---------- Slider ---------- */
  function range(input) {
    const out = input.id ? document.querySelector(`output[for~="${input.id}"]`) : null;
    const fmt = new Intl.NumberFormat("id-ID");
    const update = () => {
      const min = +input.min || 0, max = +input.max || 100;
      input.style.setProperty("--pct", `${((input.value - min) / (max - min)) * 100}%`);
      if (out) out.textContent = `${input.dataset.prefix || ""}${fmt.format(+input.value)}${input.dataset.suffix || ""}`;
    };
    input.addEventListener("input", update);
    update();
  }

  /* ---------- Combobox (Tom Select) ---------- */
  function combobox(select) {
    if (!window.TomSelect || select.tomselect) return;
    const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    const avatar = (data) => (data.initials ? `<span class="avatar avatar--sm${data.accent ? " avatar--accent" : ""}">${esc(data.initials)}</span>` : "");
    new window.TomSelect(select, {
      create: false,
      maxOptions: null,
      allowEmptyOption: false,
      hidePlaceholder: true,
      plugins: select.multiple ? { remove_button: { title: "Hapus" } } : {},
      render: {
        option: (data, e) => `<div>${avatar(data)}<span>${e(data.text)}</span>${data.hint ? `<small>${e(data.hint)}</small>` : ""}</div>`,
        item: (data, e) => `<div>${e(data.text)}</div>`,
        no_results: (data, e) => `<div class="no-results">Tidak ada yang cocok dengan "${e(data.input)}"</div>`,
      },
    });
  }

  /* ---------- Tabel interaktif ---------- */
  function table(root) {
    const rows = () => [...root.querySelectorAll("tbody tr:not(.table-empty-row)")];
    const search = root.querySelector("[data-table-search]");
    const chips = [...root.querySelectorAll("[data-table-filter]")];
    const all = root.querySelector("[data-select-all]");
    const bar = root.querySelector("[data-bulk-bar]");
    const count = root.querySelector("[data-bulk-count]");
    const empty = root.querySelector(".table-empty-row");
    let filter = chips.find((c) => c.getAttribute("aria-pressed") === "true")?.dataset.value || "";
    function apply() {
      const q = (search?.value || "").trim().toLowerCase();
      let shown = 0;
      rows().forEach((r) => {
        const ok = (!q || r.textContent.toLowerCase().includes(q)) && (!filter || r.dataset.status === filter);
        r.hidden = !ok;
        if (ok) shown++;
      });
      if (empty) empty.hidden = shown > 0;
      sel();
    }
    function sel() {
      const visible = rows().filter((r) => !r.hidden);
      const picked = visible.filter((r) => r.querySelector("[data-select-row]")?.checked);
      rows().forEach((r) => r.setAttribute("aria-selected", String(!!r.querySelector("[data-select-row]")?.checked)));
      if (all) { all.checked = picked.length > 0 && picked.length === visible.length; all.indeterminate = picked.length > 0 && picked.length < visible.length; }
      if (bar) bar.hidden = picked.length === 0;
      if (count) count.textContent = `${picked.length} tamu dipilih`;
    }
    search?.addEventListener("input", apply);
    chips.forEach((c) => c.addEventListener("click", () => {
      chips.forEach((o) => o.setAttribute("aria-pressed", String(o === c)));
      filter = c.dataset.value || "";
      apply();
    }));
    all?.addEventListener("change", () => { rows().filter((r) => !r.hidden).forEach((r) => { const b = r.querySelector("[data-select-row]"); if (b) b.checked = all.checked; }); sel(); });
    root.addEventListener("change", (e) => { if (e.target.matches("[data-select-row]")) sel(); });
    root.querySelectorAll("[data-bulk-clear]").forEach((b) => b.addEventListener("click", () => { rows().forEach((r) => { const c = r.querySelector("[data-select-row]"); if (c) c.checked = false; }); sel(); }));
    apply();
  }

  /* ---------- Form bertahap ---------- */
  function wizard(form) {
    const panels = [...form.querySelectorAll(".wizard__panel")];
    const steps = [...form.querySelectorAll(".steps > li")];
    const prev = form.querySelector("[data-wizard-prev]");
    const next = form.querySelector("[data-wizard-next]");
    const submit = form.querySelector("[data-wizard-submit]");
    const label = form.querySelector("[data-wizard-label]");
    let i = 0;
    function show(n) {
      i = n;
      panels.forEach((p, k) => { p.hidden = k !== i; });
      steps.forEach((s, k) => {
        if (k < i) s.dataset.state = "done"; else if (k === i) s.dataset.state = "current"; else delete s.dataset.state;
        if (k === i) s.setAttribute("aria-current", "step"); else s.removeAttribute("aria-current");
      });
      if (prev) prev.hidden = i === 0;
      if (next) next.hidden = i === panels.length - 1;
      if (submit) submit.hidden = i !== panels.length - 1;
      if (label) label.textContent = `Langkah ${i + 1} dari ${panels.length}`;
      if (i === panels.length - 1) summary();
    }
    function valid() {
      const fields = [...panels[i].querySelectorAll("input, select, textarea")];
      let ok = true;
      fields.forEach((f) => {
        const good = f.checkValidity();
        if (f.type !== "radio" && f.type !== "checkbox") f.setAttribute("aria-invalid", String(!good));
        if (!good && ok) { ok = false; f.reportValidity(); f.focus(); }
      });
      return ok;
    }
    function summary() {
      const out = form.querySelector("[data-wizard-summary]");
      if (!out) return;
      out.replaceChildren();
      form.querySelectorAll("[data-summary]").forEach((f) => {
        if ((f.type === "radio" || f.type === "checkbox") && !f.checked) return;
        const dt = document.createElement("dt"); dt.textContent = f.dataset.summary;
        const dd = document.createElement("dd");
        const hidden = f.parentElement.querySelector("[data-picker-value]");
        dd.textContent = f.tagName === "SELECT" ? f.selectedOptions[0]?.textContent : (f.type === "radio" ? f.dataset.summaryValue || f.value : f.value || (hidden ? hidden.value : "")) || "—";
        out.append(dt, dd);
      });
    }
    next?.addEventListener("click", () => { if (valid()) show(i + 1); });
    prev?.addEventListener("click", () => show(i - 1));
    form.addEventListener("submit", (e) => {
      e.preventDefault();
      if (!valid()) return;
      form.dispatchEvent(new CustomEvent("origin:wizard-done", { bubbles: true }));
      UI.toast({ type: "success", title: "Undangan dibuat", text: "Link tamu siap dikirim lewat WhatsApp." });
    });
    form.addEventListener("input", (e) => { if (e.target.getAttribute("aria-invalid") === "true" && e.target.checkValidity()) e.target.setAttribute("aria-invalid", "false"); });
    show(0);
  }

  /* ---------- Pencarian cepat (Ctrl+K) ---------- */
  function cmdk(dlg) {
    const input = dlg.querySelector(".cmdk__search input");
    const empty = dlg.querySelector(".cmdk__empty");
    const items = () => [...dlg.querySelectorAll(".cmdk__item")].filter((x) => !x.closest("li").hidden);
    const select = (el) => { dlg.querySelectorAll(".cmdk__item").forEach((x) => x.setAttribute("aria-selected", String(x === el))); el?.scrollIntoView({ block: "nearest" }); if (el) input.setAttribute("aria-activedescendant", el.id); };
    dlg.querySelectorAll(".cmdk__item").forEach((x, n) => { x.id = x.id || `cmdk-item-${n}`; x.setAttribute("role", "option"); x.tabIndex = -1; });
    function filter() {
      const q = input.value.trim().toLowerCase();
      dlg.querySelectorAll(".cmdk__item").forEach((x) => { x.closest("li").hidden = q && !`${x.textContent} ${x.dataset.keywords || ""}`.toLowerCase().includes(q); });
      dlg.querySelectorAll(".cmdk__group").forEach((g) => {
        let n = g.parentElement.nextElementSibling, any = false;
        while (n && !n.querySelector(".cmdk__group")) { if (!n.hidden) any = true; n = n.nextElementSibling; }
        g.parentElement.hidden = !any;
      });
      const list = items();
      if (empty) empty.hidden = list.length > 0;
      select(list[0]);
    }
    function run(el) {
      if (!el) return;
      const action = el.dataset.action;
      dlg.close();
      if (action?.startsWith("theme-")) UI.setTheme(action.slice(6));
      else if (action) dlg.dispatchEvent(new CustomEvent("origin:command", { bubbles: true, detail: { action, item: el } }));
      else if (el.href) location.href = el.href;
    }
    input.addEventListener("input", filter);
    input.addEventListener("keydown", (e) => {
      const list = items();
      const cur = list.findIndex((x) => x.getAttribute("aria-selected") === "true");
      if (e.key === "ArrowDown" || e.key === "ArrowUp") { e.preventDefault(); select(list[(cur + (e.key === "ArrowDown" ? 1 : -1) + list.length) % list.length]); }
      else if (e.key === "Enter") { e.preventDefault(); run(list[cur]); }
    });
    dlg.addEventListener("click", (e) => { const x = e.target.closest(".cmdk__item"); if (x) { e.preventDefault(); run(x); } });
    dlg.addEventListener("close", () => { input.value = ""; filter(); });
    dlg._open = () => { if (!dlg.open) { dlg.showModal(); filter(); input.focus(); } };
    filter();
  }
  document.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
      const dlg = document.querySelector("dialog[data-cmdk]");
      if (!dlg?._open) return;
      e.preventDefault();
      dlg.open ? dlg.close() : dlg._open();
    }
  });
  document.addEventListener("click", (e) => {
    const b = e.target.closest("[data-cmdk-open]");
    if (b) document.querySelector("dialog[data-cmdk]")?._open?.();
    const rm = e.target.closest("[data-tag-remove]");
    if (rm) {
      const tag = rm.closest("li") || rm.closest(".tag");
      const group = tag.parentElement;
      const nextBtn = tag.nextElementSibling?.querySelector("[data-tag-remove]") || tag.previousElementSibling?.querySelector("[data-tag-remove]");
      tag.remove();
      (nextBtn || group).focus?.();
      group.dispatchEvent(new CustomEvent("origin:tag-removed", { bubbles: true, detail: { label: rm.getAttribute("aria-label") } }));
    }
    const press = e.target.closest("[data-toggle-pressed]");
    if (press) {
      const on = press.getAttribute("aria-pressed") !== "true";
      press.setAttribute("aria-pressed", String(on));
      const n = press.querySelector("[data-count]");
      if (n) n.textContent = String(+n.textContent + (on ? 1 : -1));
    }
    const lm = e.target.closest("[data-load-more]");
    if (lm) loadMore(lm);
    const emb = e.target.closest("[data-embed-load]");
    if (emb) loadEmbed(emb.closest(".embed"));
  });

  /* ---------- Lazy loading ---------- */
  function lazyImg(box) {
    const img = box.querySelector("img");
    if (!img) return;
    const done = () => box.setAttribute("data-loaded", "");
    if (img.complete && img.naturalWidth) done();
    else { img.addEventListener("load", done, { once: true }); img.addEventListener("error", () => box.setAttribute("data-error", ""), { once: true }); }
  }
  function revealBlock(block) {
    const tpl = block.querySelector("template");
    if (!tpl) return;
    setTimeout(() => {
      block.replaceChildren(tpl.content.cloneNode(true));
      block.setAttribute("data-loaded", "");
      block.querySelectorAll("[data-chart]").forEach((c) => UI.chart(c));
      block.querySelectorAll("svg[data-spark]").forEach(UI.sparkline);
      block.querySelectorAll(".lazy-img").forEach(lazyImg);
      block.dispatchEvent(new CustomEvent("origin:lazy-loaded", { bubbles: true }));
    }, +(block.dataset.lazyDelay || 0));
  }
  const io = "IntersectionObserver" in window ? new IntersectionObserver((entries) => {
    entries.forEach((en) => { if (en.isIntersecting) { io.unobserve(en.target); revealBlock(en.target); } });
  }, { rootMargin: "200px 0px" }) : null;

  function takeChunk(source, n) {
    const tpl = document.querySelector(source);
    if (!tpl) return [];
    const items = [...tpl.content.children].slice(0, n);
    items.forEach((x) => x.remove());
    return items;
  }
  function loadMore(btn) {
    if (btn.getAttribute("aria-busy") === "true") return;
    const list = document.querySelector(btn.dataset.loadMore);
    btn.setAttribute("aria-busy", "true");
    setTimeout(() => {
      const items = takeChunk(btn.dataset.source, +(btn.dataset.chunk || 5));
      items.forEach((x) => list.append(x));
      btn.removeAttribute("aria-busy");
      const left = document.querySelector(btn.dataset.source)?.content.children.length || 0;
      const note = btn.parentElement.querySelector("[data-load-note]");
      if (note) note.textContent = left ? `${left} tamu lagi belum ditampilkan` : "Semua tamu sudah tampil";
      if (!left) { btn.disabled = true; btn.textContent = "Semua sudah dimuat"; }
      btn.dispatchEvent(new CustomEvent("origin:load-more", { bubbles: true, detail: { added: items.length, left } }));
    }, +(btn.dataset.delay || 500));
  }
  function infinite(box) {
    const sentinel = box.querySelector(".infinite__sentinel");
    const list = box.querySelector(box.dataset.list || ".list");
    if (!sentinel || !list || !("IntersectionObserver" in window)) return;
    let busy = false;
    const obs = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting || busy) return;
      busy = true;
      setTimeout(() => {
        const items = takeChunk(box.dataset.source, +(box.dataset.chunk || 5));
        items.forEach((x) => list.append(x));
        busy = false;
        if (!items.length || !document.querySelector(box.dataset.source)?.content.children.length) {
          sentinel.setAttribute("data-done", "");
          sentinel.querySelector("[data-infinite-label]").textContent = "Sudah sampai akhir daftar";
          obs.disconnect();
        }
      }, +(box.dataset.delay || 600));
    }, { root: box, rootMargin: "60px" });
    obs.observe(sentinel);
  }
  function loadEmbed(box) {
    if (!box || box.querySelector("iframe")) return;
    const ev = new CustomEvent("origin:embed", { bubbles: true, cancelable: true, detail: { src: box.dataset.embedSrc } });
    if (!box.dispatchEvent(ev)) return;
    const f = document.createElement("iframe");
    f.src = box.dataset.embedSrc;
    f.title = box.dataset.embedTitle || "Konten tersemat";
    f.loading = "lazy";
    f.referrerPolicy = "strict-origin-when-cross-origin";
    f.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; picture-in-picture; fullscreen";
    f.allowFullscreen = true;
    box.querySelector(".embed__poster")?.remove();
    box.append(f);
  }

  const init = () => {
    document.querySelectorAll("[data-datepicker]").forEach(datepicker);
    document.querySelectorAll("[data-timepicker]").forEach(timepicker);
    document.querySelectorAll("input.range").forEach(range);
    document.querySelectorAll("select[data-combobox]").forEach(combobox);
    document.querySelectorAll("[data-table]").forEach(table);
    document.querySelectorAll("form[data-wizard]").forEach(wizard);
    document.querySelectorAll("dialog[data-cmdk]").forEach(cmdk);
    document.querySelectorAll(".lazy-img").forEach(lazyImg);
    document.querySelectorAll(".lazy-block").forEach((b) => (io ? io.observe(b) : revealBlock(b)));
    document.querySelectorAll("[data-infinite]").forEach(infinite);
    window.addEventListener("resize", () => {
      document.querySelectorAll('.offcanvas-backdrop[data-open="true"]').forEach((b) => {
        const t = document.getElementById(b.dataset.for);
        if (t && getComputedStyle(t).position !== "fixed") UI.setPanel(b.dataset.for, false);
      });
    });
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();

  Object.assign(UI, { extras: true, datepicker, timepicker, range, combobox, table, wizard, cmdk, lazyImg, loadMore, loadEmbed });
})();

/* Origin Design System v2 — skeleton, acara (musik, sampul, hitung mundur, kalender, RSVP),
   admin (unggah, editor, cetak, notifikasi, kanban, tab vertikal), landing (filter, carousel,
   banner dan cookie). Butuh origin.js dimuat lebih dulu. */
(() => {
  const UI = window.OriginUI;
  if (!UI || UI.v2) return;
  const icon = UI.icon;
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];
  const reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const store = {
    get(k) { try { return localStorage.getItem(k); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, v); } catch (e) { /* mode privat */ } },
  };
  const fire = (el, name, detail, cancelable = false) => el.dispatchEvent(new CustomEvent(name, { bubbles: true, cancelable, detail }));

  /* ---------- Gerak dikurangi: hentikan animasi SVG (SMIL) ---------- */
  function calmSvg(root = document) {
    if (!reduced()) return;
    $$("svg", root).forEach((s) => { if (s.querySelector("animateMotion, animate, animateTransform")) s.pauseAnimations?.(); });
  }

  /* ---------- Skeleton ---------- */
  const skeletonStore = new WeakMap();
  function skeletonDone(el, content) {
    const tpl = el.querySelector(":scope > template");
    if (!skeletonStore.has(el)) skeletonStore.set(el, el.innerHTML);
    if (content instanceof Node) el.replaceChildren(content);
    else if (typeof content === "string") el.innerHTML = content;
    else if (tpl) el.replaceChildren(tpl.content.cloneNode(true));
    el.setAttribute("aria-busy", "false");
    $$("[data-chart]", el).forEach((c) => UI.chart(c));
    $$("svg[data-spark]", el).forEach(UI.sparkline);
    fire(el, "origin:skeleton-done");
  }
  function skeletonReset(el) {
    if (!skeletonStore.has(el)) return;
    el.innerHTML = skeletonStore.get(el);
    el.setAttribute("aria-busy", "true");
    watchSkeleton(el);
  }
  const skIO = "IntersectionObserver" in window ? new IntersectionObserver((list) => {
    list.forEach((en) => {
      if (!en.isIntersecting) return;
      skIO.unobserve(en.target);
      setTimeout(() => skeletonDone(en.target), +(en.target.dataset.skeletonDelay || 0));
    });
  }, { rootMargin: "100px 0px" }) : null;
  function watchSkeleton(el) {
    if (!skeletonStore.has(el)) skeletonStore.set(el, el.innerHTML);
    if (el.dataset.skeleton === "manual") return;
    if (skIO) skIO.observe(el); else skeletonDone(el);
  }

  /* ---------- Musik latar ---------- */
  function setAudio(btn, on) {
    const audio = document.getElementById(btn.dataset.audio);
    const apply = (state) => {
      btn.setAttribute("aria-pressed", String(state));
      btn.setAttribute("aria-label", state ? (btn.dataset.labelOn || "Matikan musik") : (btn.dataset.labelOff || "Putar musik"));
    };
    if (audio && (audio.currentSrc || audio.src || audio.querySelector("source"))) {
      if (on) audio.play().then(() => apply(true)).catch(() => apply(false));
      else { audio.pause(); apply(false); }
    } else apply(on);
  }

  /* ---------- Sampul pembuka ---------- */
  function openCover(cover) {
    cover.setAttribute("data-open", "");
    if (!cover.classList.contains("cover--inline")) document.documentElement.style.removeProperty("overflow");
    const a = cover.dataset.coverAudio && document.querySelector(cover.dataset.coverAudio);
    if (a && a.getAttribute("aria-pressed") !== "true") setAudio(a, true);
    fire(cover, "origin:cover-open");
    const next = document.querySelector(cover.dataset.coverFocus || "main");
    if (next) { if (!next.hasAttribute("tabindex")) next.setAttribute("tabindex", "-1"); next.focus({ preventScroll: true }); }
  }
  function closeCover(cover) {
    cover.removeAttribute("data-open");
    if (!cover.classList.contains("cover--inline")) document.documentElement.style.overflow = "hidden";
  }

  /* ---------- Nama tamu dari link (?to=Nama) ---------- */
  function guestName() {
    const params = new URLSearchParams(location.search);
    $$("[data-guest]").forEach((el) => {
      const v = (params.get(el.dataset.guest || "to") || "").replace(/\s+/g, " ").trim().slice(0, 60);
      if (v) el.textContent = v;
    });
  }

  /* ---------- Hitung mundur ---------- */
  const pad = (n) => String(n).padStart(2, "0");
  function tickCountdowns() {
    $$("[data-countdown]").forEach((el) => {
      const end = Date.parse(el.dataset.countdown);
      if (Number.isNaN(end)) return;
      let s = Math.max(0, Math.floor((end - Date.now()) / 1000));
      const parts = { days: Math.floor(s / 86400), hours: Math.floor((s % 86400) / 3600), minutes: Math.floor((s % 3600) / 60), seconds: s % 60 };
      Object.entries(parts).forEach(([k, v]) => { const n = el.querySelector(`[data-unit="${k}"]`); if (n) n.textContent = k === "days" ? String(v) : pad(v); });
      if (s === 0 && !el.hasAttribute("data-done")) { el.setAttribute("data-done", ""); fire(el, "origin:countdown-done"); }
    });
  }

  /* ---------- Simpan ke kalender (.ics) dan Google Calendar ---------- */
  const icsDate = (s) => new Date(s).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const icsEsc = (s = "") => s.replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/[,;]/g, (c) => `\\${c}`);
  function eventData(el) {
    const d = el.dataset;
    return { title: d.title || document.title, start: d.start, end: d.end || d.start, location: d.location || "", details: d.details || "" };
  }
  function downloadIcs(el) {
    const ev = eventData(el);
    if (!ev.start || !fire(el, "origin:ics", ev, true)) return;
    const body = [
      "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Origin//ID", "CALSCALE:GREGORIAN", "BEGIN:VEVENT",
      `UID:${Date.now()}@origin`, `DTSTAMP:${icsDate(Date.now())}`, `DTSTART:${icsDate(ev.start)}`, `DTEND:${icsDate(ev.end)}`,
      `SUMMARY:${icsEsc(ev.title)}`, `LOCATION:${icsEsc(ev.location)}`, `DESCRIPTION:${icsEsc(ev.details)}`, "END:VEVENT", "END:VCALENDAR",
    ].join("\r\n");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([body], { type: "text/calendar;charset=utf-8" }));
    a.download = `${ev.title.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") || "acara"}.ics`;
    document.body.append(a);
    a.click();
    setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  }
  function gcalUrl(ev) {
    const q = new URLSearchParams({ action: "TEMPLATE", text: ev.title, dates: `${icsDate(ev.start)}/${icsDate(ev.end)}`, location: ev.location, details: ev.details });
    return `https://calendar.google.com/calendar/render?${q}`;
  }

  /* ---------- Stepper angka ---------- */
  function stepper(root) {
    const input = root.querySelector("input");
    const [minus, plus] = $$("button[data-step]", root).sort((a, b) => +a.dataset.step - +b.dataset.step);
    const min = input.min === "" ? -Infinity : +input.min;
    const max = input.max === "" ? Infinity : +input.max;
    const sync = () => { const v = +input.value || 0; if (minus) minus.disabled = v <= min; if (plus) plus.disabled = v >= max; };
    root.addEventListener("click", (e) => {
      const b = e.target.closest("button[data-step]");
      if (!b) return;
      input.value = String(Math.min(max, Math.max(min, (+input.value || 0) + +b.dataset.step)));
      input.dispatchEvent(new Event("input", { bubbles: true }));
      input.dispatchEvent(new Event("change", { bubbles: true }));
      sync();
    });
    input.addEventListener("input", sync);
    sync();
  }

  /* ---------- Isian bersyarat: data-show-if="name=value" ---------- */
  function showIf(form) {
    const rules = $$("[data-show-if]", form);
    const run = () => rules.forEach((el) => {
      const [name, want] = el.dataset.showIf.split("=");
      const field = form.elements[name];
      const value = field instanceof RadioNodeList ? field.value : field?.type === "checkbox" ? String(field.checked) : field?.value;
      const show = want.split("|").includes(value);
      el.hidden = !show;
      $$("input, select, textarea", el).forEach((x) => { x.disabled = !show; });
    });
    form.addEventListener("change", run);
    run();
  }

  /* ---------- Unggah banyak file ---------- */
  const fmtSize = (b) => (b < 1024 * 1024 ? `${Math.max(1, Math.round(b / 1024))} KB` : `${(b / 1048576).toFixed(1).replace(".", ",")} MB`);
  function upload(input) {
    const list = document.querySelector(input.dataset.upload);
    if (!list) return;
    const maxMb = +(input.dataset.maxMb || 0);
    input.addEventListener("change", () => {
      [...input.files].forEach((file) => {
        const li = document.createElement("li");
        li.className = "upload-item";
        li.dataset.state = "uploading";
        const isImg = file.type.startsWith("image/");
        li.innerHTML = `<span class="upload-item__thumb">${isImg ? "<img alt=\"\">" : icon("file-text")}</span><div class="upload-item__body"><span class="upload-item__name"></span><div class="progress" role="progressbar" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><span style="width:0%"></span></div><span class="upload-item__meta"></span></div><button class="btn btn--ghost btn--icon btn--sm" type="button" data-upload-remove>${icon("x")}</button>`;
        li.querySelector(".upload-item__name").textContent = file.name;
        li.querySelector("[data-upload-remove]").setAttribute("aria-label", `Hapus ${file.name}`);
        if (isImg) { const url = URL.createObjectURL(file); const img = li.querySelector("img"); img.src = url; img.onload = () => URL.revokeObjectURL(url); }
        const meta = li.querySelector(".upload-item__meta");
        const bar = li.querySelector(".progress");
        const api = {
          file, item: li,
          progress(p) { const v = Math.round(Math.min(100, Math.max(0, p))); bar.setAttribute("aria-valuenow", v); bar.firstElementChild.style.width = `${v}%`; meta.textContent = `${fmtSize(file.size)} · ${v}%`; },
          done(text = "Selesai diunggah") { li.dataset.state = "done"; meta.textContent = `${fmtSize(file.size)} · ${text}`; },
          fail(text = "Gagal diunggah") { li.dataset.state = "error"; meta.textContent = `${fmtSize(file.size)} · ${text}`; },
        };
        api.progress(0);
        list.append(li);
        if (maxMb && file.size > maxMb * 1048576) { api.fail(`Lebih dari ${maxMb} MB`); return; }
        fire(input, "origin:upload", api);
        if (input.hasAttribute("data-upload-simulate")) {
          let p = 0;
          const t = setInterval(() => { p += 8 + Math.random() * 18; api.progress(p); if (p >= 100) { clearInterval(t); api.done(); } }, 180);
        }
      });
      input.value = "";
    });
    const drop = input.closest(".file-drop");
    if (drop) {
      drop.addEventListener("dragover", (e) => { e.preventDefault(); drop.setAttribute("data-drag", ""); });
      drop.addEventListener("dragleave", () => drop.removeAttribute("data-drag"));
      drop.addEventListener("drop", (e) => {
        e.preventDefault();
        drop.removeAttribute("data-drag");
        if (!e.dataTransfer?.files.length) return;
        input.files = e.dataTransfer.files;
        input.dispatchEvent(new Event("change", { bubbles: true }));
      });
    }
  }

  /* ---------- Editor teks ---------- */
  function editor(root) {
    const area = root.querySelector(".editor__content");
    const out = root.querySelector("[data-editor-input]");
    const count = root.querySelector("[data-editor-count]");
    const max = +(root.dataset.max || 0);
    const buttons = $$("[data-cmd]", root);
    const sync = () => {
      if (area.innerHTML === "<br>") area.innerHTML = "";
      if (out) out.value = area.innerHTML;
      if (count) { const n = area.textContent.length; count.textContent = max ? `${n} / ${max}` : `${n} karakter`; count.style.color = max && n > max ? "var(--danger-soft-text)" : ""; }
    };
    const state = () => buttons.forEach((b) => {
      if (["bold", "italic", "insertUnorderedList", "insertOrderedList"].includes(b.dataset.cmd)) {
        let on = false;
        try { on = document.queryCommandState(b.dataset.cmd); } catch (e) { /* tidak didukung */ }
        b.setAttribute("aria-pressed", String(on));
      }
    });
    root.addEventListener("mousedown", (e) => { if (e.target.closest("[data-cmd]")) e.preventDefault(); });
    root.addEventListener("click", (e) => {
      const b = e.target.closest("[data-cmd]");
      if (!b) return;
      area.focus();
      document.execCommand(b.dataset.cmd, false, b.dataset.value || null);
      sync(); state();
    });
    area.addEventListener("input", sync);
    area.addEventListener("keyup", state);
    area.addEventListener("mouseup", state);
    area.addEventListener("paste", (e) => {
      e.preventDefault();
      document.execCommand("insertText", false, e.clipboardData.getData("text/plain"));
    });
    sync();
  }

  /* ---------- Cetak satu elemen ---------- */
  function print(el) {
    if (!el) return;
    const html = document.documentElement;
    const path = [];
    for (let p = el.parentElement; p && p !== document.body; p = p.parentElement) { p.classList.add("print-path"); path.push(p); }
    el.classList.add("print-target");
    html.classList.add("is-printing");
    const done = () => { el.classList.remove("print-target"); path.forEach((p) => p.classList.remove("print-path")); html.classList.remove("is-printing"); window.removeEventListener("afterprint", done); };
    window.addEventListener("afterprint", done);
    window.print();
    setTimeout(done, 1000);
  }

  /* ---------- Notifikasi ---------- */
  function notifCount(panel) {
    const n = $$("[data-unread]", panel).length;
    const badge = panel.closest("details")?.querySelector(".dot-badge") || document.querySelector(panel.dataset.badge || "_");
    if (badge) {
      badge.dataset.count = String(n);
      badge.setAttribute("aria-label", n ? `Notifikasi, ${n} belum dibaca` : "Notifikasi");
    }
  }

  /* ---------- Kanban ---------- */
  function kanban(root) {
    const lists = () => $$("[data-kanban-list]", root);
    const live = root.querySelector("[data-kanban-live]");
    let dragged = null;
    const update = () => {
      const all = lists();
      all.forEach((l, i) => {
        const col = l.closest(".kanban__col");
        const c = col?.querySelector("[data-kanban-count]");
        if (c) c.textContent = String(l.children.length);
        $$(".kanban__card", l).forEach((card) => {
          card.querySelector('[data-kanban-move="prev"]')?.toggleAttribute("disabled", i === 0);
          card.querySelector('[data-kanban-move="next"]')?.toggleAttribute("disabled", i === all.length - 1);
        });
      });
    };
    const moved = (card, list) => {
      const name = list.closest(".kanban__col")?.querySelector(".kanban__head strong")?.textContent || "";
      const title = card.querySelector("strong")?.textContent || "Kartu";
      if (live) live.textContent = `${title} dipindah ke ${name}`;
      fire(root, "origin:kanban-move", { card, list, column: name });
      update();
    };
    root.addEventListener("dragstart", (e) => {
      dragged = e.target.closest(".kanban__card");
      if (!dragged) return;
      dragged.setAttribute("data-dragging", "");
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", "");
    });
    root.addEventListener("dragend", () => { dragged?.removeAttribute("data-dragging"); lists().forEach((l) => l.removeAttribute("data-drop-over")); dragged = null; });
    root.addEventListener("dragover", (e) => {
      const list = e.target.closest("[data-kanban-list]");
      if (!list || !dragged) return;
      e.preventDefault();
      lists().forEach((l) => l.toggleAttribute("data-drop-over", l === list));
      const after = [...list.children].find((c) => c !== dragged && e.clientY < c.getBoundingClientRect().top + c.offsetHeight / 2);
      list.insertBefore(dragged, after || null);
    });
    root.addEventListener("drop", (e) => {
      const list = e.target.closest("[data-kanban-list]");
      if (!list || !dragged) return;
      e.preventDefault();
      list.removeAttribute("data-drop-over");
      moved(dragged, list);
    });
    root.addEventListener("click", (e) => {
      const b = e.target.closest("[data-kanban-move]");
      if (!b) return;
      const card = b.closest(".kanban__card");
      const all = lists();
      const i = all.indexOf(card.parentElement) + (b.dataset.kanbanMove === "next" ? 1 : -1);
      if (!all[i]) return;
      all[i].append(card);
      moved(card, all[i]);
      card.querySelector(`[data-kanban-move="${b.dataset.kanbanMove}"]:not(:disabled)`)?.focus() || card.querySelector("[data-kanban-move]:not(:disabled)")?.focus();
    });
    $$(".kanban__card", root).forEach((c) => { c.draggable = true; });
    update();
  }

  /* ---------- Filter kartu (portofolio, galeri) ---------- */
  function filterGroup(root) {
    const buttons = $$("[data-filter]", root);
    const items = $$("[data-tags]", root);
    const status = root.querySelector("[data-filter-status]");
    root.addEventListener("click", (e) => {
      const b = e.target.closest("[data-filter]");
      if (!b) return;
      buttons.forEach((x) => x.setAttribute("aria-pressed", String(x === b)));
      const f = b.dataset.filter;
      let n = 0;
      items.forEach((it) => { const ok = !f || it.dataset.tags.split(/\s+/).includes(f); it.hidden = !ok; if (ok) n++; });
      if (status) status.textContent = `${n} karya ditampilkan`;
      fire(root, "origin:filter", { filter: f, count: n });
    });
  }

  /* ---------- Carousel ---------- */
  function carousel(root) {
    const track = root.querySelector(".carousel__track");
    const prev = root.querySelector("[data-carousel-prev]");
    const next = root.querySelector("[data-carousel-next]");
    const status = root.querySelector(".carousel__status");
    if (!track) return;
    const step = () => (track.firstElementChild?.getBoundingClientRect().width || track.clientWidth) + parseFloat(getComputedStyle(track).columnGap || 0);
    const sync = () => {
      const max = track.scrollWidth - track.clientWidth - 2;
      if (prev) prev.disabled = track.scrollLeft <= 2;
      if (next) next.disabled = track.scrollLeft >= max;
      if (status) {
        const total = track.children.length;
        const first = Math.min(total, Math.round(track.scrollLeft / step()) + 1);
        const perView = Math.max(1, Math.round(track.clientWidth / step()));
        const last = Math.min(total, first + perView - 1);
        status.textContent = first === last ? `${first} dari ${total}` : `${first}–${last} dari ${total}`;
      }
    };
    prev?.addEventListener("click", () => track.scrollBy({ left: -step(), behavior: reduced() ? "auto" : "smooth" }));
    next?.addEventListener("click", () => track.scrollBy({ left: step(), behavior: reduced() ? "auto" : "smooth" }));
    track.addEventListener("scroll", () => requestAnimationFrame(sync), { passive: true });
    window.addEventListener("resize", sync);
    if (!track.hasAttribute("tabindex")) track.tabIndex = 0;
    sync();
  }

  /* ---------- Banner dan cookie yang diingat ---------- */
  function dismissible(el) {
    const key = `origin-dismiss-${el.dataset.dismissKey}`;
    if (store.get(key)) el.hidden = true;
  }

  /* ---------- Klik global ---------- */
  document.addEventListener("click", (e) => {
    const t = e.target;
    const audioBtn = t.closest("[data-audio]");
    if (audioBtn) setAudio(audioBtn, audioBtn.getAttribute("aria-pressed") !== "true");
    const co = t.closest("[data-cover-open]");
    if (co) openCover(co.closest(".cover"));
    const cr = t.closest("[data-cover-reset]");
    if (cr) { const c = document.querySelector(cr.dataset.coverReset); if (c) closeCover(c); }
    const ics = t.closest("[data-ics]");
    if (ics) downloadIcs(ics);
    const pr = t.closest("[data-print]");
    if (pr) print(document.querySelector(pr.dataset.print));
    const skr = t.closest("[data-skeleton-reload]");
    if (skr) { const el = document.querySelector(skr.dataset.skeletonReload); if (el) skeletonReset(el); }
    const rm = t.closest("[data-upload-remove]");
    if (rm) rm.closest(".upload-item")?.remove();
    const ra = t.closest("[data-notif-read-all]");
    if (ra) { const p = ra.closest(".notif-panel"); $$("[data-unread]", p).forEach((x) => x.removeAttribute("data-unread")); notifCount(p); }
    const ni = t.closest(".notif-list [data-unread]");
    if (ni) { ni.removeAttribute("data-unread"); notifCount(ni.closest(".notif-panel")); }
    const ds = t.closest("[data-dismiss-save]");
    if (ds) {
      const box = ds.closest("[data-dismiss-key]");
      if (box) {
        store.set(`origin-dismiss-${box.dataset.dismissKey}`, ds.dataset.dismissSave || "1");
        box.hidden = true;
        fire(box, "origin:dismiss", { key: box.dataset.dismissKey, value: ds.dataset.dismissSave || "1" });
      }
    }
  });

  /* Tab vertikal: panah atas/bawah */
  document.addEventListener("keydown", (e) => {
    const tab = e.target.closest?.('[role="tablist"][aria-orientation="vertical"] [role="tab"]');
    if (!tab || !["ArrowUp", "ArrowDown"].includes(e.key)) return;
    e.preventDefault();
    const tabs = $$('[role="tab"]', tab.closest('[role="tablist"]'));
    const i = (tabs.indexOf(tab) + (e.key === "ArrowDown" ? 1 : -1) + tabs.length) % tabs.length;
    UI.selectTab(tabs[i], true);
  });

  const init = () => {
    calmSvg();
    guestName();
    $$("[data-skeleton]").forEach(watchSkeleton);
    $$(".cover:not(.cover--inline):not([data-open])").forEach(() => { document.documentElement.style.overflow = "hidden"; });
    if ($$("[data-countdown]").length) { tickCountdowns(); setInterval(tickCountdowns, 1000); }
    $$("a[data-gcal]").forEach((a) => { const ev = eventData(a); if (ev.start) { a.href = gcalUrl(ev); a.target = "_blank"; a.rel = "noopener"; } });
    $$(".stepper").forEach(stepper);
    $$("form").filter((f) => f.querySelector("[data-show-if]")).forEach(showIf);
    $$("input[type=file][data-upload]").forEach(upload);
    $$(".editor").forEach(editor);
    $$(".notif-panel").forEach(notifCount);
    $$(".kanban").forEach(kanban);
    $$("[data-filter-group]").forEach(filterGroup);
    $$(".carousel").forEach(carousel);
    $$("[data-dismiss-key]").forEach(dismissible);
  };
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init); else init();

  Object.assign(UI, { v2: true, skeletonDone, skeletonReset, setAudio, openCover, closeCover, downloadIcs, gcalUrl, print, kanban, carousel, calmSvg });
})();

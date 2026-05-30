/* ============================================================
   OpenStrato — site.js
   Vanilla: theme toggle, tabs, copy buttons, mobile nav,
   banner dismiss, density, scroll reveal. No dependencies.
   ============================================================ */
(function () {
  "use strict";

  /* ---- Theme (light default, respects prefers-color-scheme, persisted) ---- */
  var root = document.documentElement;
  function applyTheme(t) {
    root.setAttribute("data-theme", t);
    try { localStorage.setItem("odc-theme", t); } catch (e) {}
  }
  (function initTheme() {
    var stored = null;
    try { stored = localStorage.getItem("odc-theme"); } catch (e) {}
    if (stored) { root.setAttribute("data-theme", stored); return; }
    var prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    root.setAttribute("data-theme", prefersDark ? "dark" : "light");
  })();

  /* ---- Density (persisted) ---- */
  (function initDensity() {
    var d = null;
    try { d = localStorage.getItem("odc-density"); } catch (e) {}
    root.setAttribute("data-density", d || "comfortable");
  })();
  function applyDensity(d) {
    root.setAttribute("data-density", d);
    try { localStorage.setItem("odc-density", d); } catch (e) {}
  }

  /* ---- Banner (persisted dismiss) ---- */
  (function initBanner() {
    var dismissed = null;
    try { dismissed = localStorage.getItem("odc-banner-dismissed"); } catch (e) {}
    if (dismissed === "1") root.setAttribute("data-banner", "off");
  })();
  function setBanner(on) {
    root.setAttribute("data-banner", on ? "on" : "off");
    try { localStorage.setItem("odc-banner-dismissed", on ? "0" : "1"); } catch (e) {}
  }

  document.addEventListener("click", function (e) {
    var t = e.target.closest("[data-action]");
    if (!t) return;
    var action = t.getAttribute("data-action");

    if (action === "toggle-theme") {
      applyTheme(root.getAttribute("data-theme") === "dark" ? "light" : "dark");
    }
    if (action === "dismiss-banner") { setBanner(false); }
    if (action === "open-mobile-nav") { document.getElementById("mobileNav").classList.add("is-open"); }
    if (action === "close-mobile-nav") { document.getElementById("mobileNav").classList.remove("is-open"); }

    /* copy buttons */
    if (action === "copy") {
      var sel = t.getAttribute("data-copy-target");
      var srcEl = sel ? document.querySelector(sel) : t.closest(".code, .terminal").querySelector("code, .terminal__body");
      if (srcEl) {
        var text = srcEl.getAttribute("data-copy") || srcEl.innerText;
        navigator.clipboard && navigator.clipboard.writeText(text);
        var label = t.querySelector(".copy-label");
        var prev = label ? label.textContent : t.textContent;
        t.classList.add("copied");
        if (label) label.textContent = "Copied"; else t.textContent = "Copied";
        setTimeout(function () {
          t.classList.remove("copied");
          if (label) label.textContent = prev; else t.textContent = prev;
        }, 1400);
      }
    }
  });

  /* ---- Tabs ---- */
  document.querySelectorAll("[data-tabs]").forEach(function (group) {
    var tabs = group.querySelectorAll(".tabs__tab");
    var panels = group.querySelectorAll(".tabs__panel");
    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () {
        tabs.forEach(function (x) { x.setAttribute("aria-selected", "false"); });
        panels.forEach(function (p) { p.classList.remove("is-active"); });
        tab.setAttribute("aria-selected", "true");
        var panel = group.querySelector("#" + tab.getAttribute("aria-controls"));
        if (panel) panel.classList.add("is-active");
      });
    });
  });

  /* ---- Scroll reveal ---- */
  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) { en.target.classList.add("in"); io.unobserve(en.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -40px 0px" });
    document.querySelectorAll(".reveal").forEach(function (el) { io.observe(el); });
  } else {
    document.querySelectorAll(".reveal").forEach(function (el) { el.classList.add("in"); });
  }

  /* ---- Docs: active section in TOC + sidebar collapse ---- */
  var tocLinks = document.querySelectorAll("[data-toc] a");
  if (tocLinks.length && "IntersectionObserver" in window) {
    var map = {};
    tocLinks.forEach(function (l) {
      var id = l.getAttribute("href").slice(1);
      var sec = document.getElementById(id);
      if (sec) map[id] = l;
    });
    var tio = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting) {
          tocLinks.forEach(function (l) { l.classList.remove("is-active"); });
          if (map[en.target.id]) map[en.target.id].classList.add("is-active");
        }
      });
    }, { rootMargin: "-80px 0px -70% 0px" });
    Object.keys(map).forEach(function (id) { var s = document.getElementById(id); if (s) tio.observe(s); });
  }

  document.querySelectorAll("[data-collapse]").forEach(function (head) {
    head.addEventListener("click", function () {
      var group = head.closest(".docnav__group");
      if (group) group.classList.toggle("is-collapsed");
    });
  });

  /* ---- Expose for review panel ---- */
  window.ODC = {
    applyTheme: applyTheme,
    applyDensity: applyDensity,
    setBanner: setBanner,
    getState: function () {
      return {
        theme: root.getAttribute("data-theme"),
        density: root.getAttribute("data-density"),
        banner: root.getAttribute("data-banner") !== "off"
      };
    }
  };
})();

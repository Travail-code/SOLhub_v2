/* Flags JS as available: scroll-reveal styles only apply with html.js (content stays visible without JS) */
document.documentElement.classList.add("js");

/* ============================================================
   SOL Hub — Get Key
   ------------------------------------------------------------
   KEY LINKS: put your 5 links here (one per line, in quotes).
   One of them is picked at random each time "Get Key" is clicked.
   Empty or invalid entries (not http/https) are ignored.
   ============================================================ */
var KEY_LINKS = [
  "https://example.com/key1",
  "https://example.com/key2",
  "https://example.com/key3",
  "https://example.com/key4",
  "https://example.com/key5"
];

/* Delay (ms) showing the "Redirecting..." state before leaving */
var REDIRECT_DELAY = 800;
/* Safety net (ms): if we are still on this page after this, the button is reset */
var RESET_TIMEOUT = 12000;

(function () {
  "use strict";

  // Keep only non-empty, valid http(s) URLs
  function validLinks(list) {
    var out = [];
    for (var i = 0; i < list.length; i++) {
      var s = typeof list[i] === "string" ? list[i].trim() : "";
      if (!s) continue;
      try {
        var u = new URL(s);
        if (u.protocol === "http:" || u.protocol === "https:") out.push(u.href);
      } catch (e) { /* invalid, skip */ }
    }
    return out;
  }

  // Random integer in [0, n) — crypto when available, Math.random otherwise; -1 if n <= 0
  function randomIndex(n) {
    if (n <= 0) return -1;
    var c = window.crypto;
    if (c && typeof c.getRandomValues === "function") {
      var buf = new Uint32Array(1);
      var limit = Math.floor(0x100000000 / n) * n; // avoid modulo bias
      do { c.getRandomValues(buf); } while (buf[0] >= limit);
      return buf[0] % n;
    }
    return Math.floor(Math.random() * n);
  }

  function pickLink() {
    var links = validLinks(KEY_LINKS);
    var i = randomIndex(links.length);
    return i < 0 ? null : links[i];
  }

  var btn = document.getElementById("getKeyBtn");
  var label = btn.querySelector(".btn-label");
  var status = document.getElementById("status");
  var footer = document.getElementById("footer");
  var systemState = document.getElementById("systemState");
  var busy = false;
  var redirectTimer = null;
  var resetTimer = null;

  // Put the button back to its idle state
  function reset() {
    busy = false;
    clearTimeout(redirectTimer);
    clearTimeout(resetTimer);
    btn.classList.remove("is-loading");
    btn.removeAttribute("aria-busy");
    btn.removeAttribute("aria-disabled");
    label.textContent = "Get Key";
    status.textContent = "";
    status.classList.remove("is-error");
  }

  // exposed for testing
  window.SOLHub = { pickLink: pickLink, validLinks: validLinks, randomIndex: randomIndex, reset: reset };

  // Footer shows "offline" when no valid link is configured
  if (validLinks(KEY_LINKS).length === 0) {
    footer.classList.add("is-offline");
    systemState.textContent = "Key system offline";
  }

  btn.addEventListener("click", function () {
    if (busy) return; // ignore double clicks
    var link = pickLink();
    if (!link) {
      status.textContent = "No key link available right now.";
      status.classList.add("is-error");
      return;
    }
    busy = true;
    status.classList.remove("is-error");
    status.textContent = "Redirecting to your key link...";
    btn.classList.add("is-loading");
    btn.setAttribute("aria-busy", "true");
    btn.setAttribute("aria-disabled", "true");
    label.textContent = "Redirecting...";
    redirectTimer = setTimeout(function () {
      window.location.href = link;
      resetTimer = setTimeout(reset, RESET_TIMEOUT); // never stay stuck on "Redirecting..."
    }, REDIRECT_DELAY);
  });

  // Footer year
  var year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());

  // Light scroll-reveal animations (skipped with prefers-reduced-motion or no IntersectionObserver)
  var reveals = document.querySelectorAll(".reveal");
  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  function showAll() {
    for (var r = 0; r < reveals.length; r++) reveals[r].classList.add("is-visible");
  }
  if (reduceMotion || !("IntersectionObserver" in window)) {
    showAll();
  } else {
    document.documentElement.classList.add("io"); // observer active: disable the CSS 2 s fallback
    var io = new IntersectionObserver(function (entries) {
      for (var k = 0; k < entries.length; k++) {
        if (entries[k].isIntersecting) {
          entries[k].target.classList.add("is-visible");
          io.unobserve(entries[k].target);
        }
      }
    }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });
    for (var r2 = 0; r2 < reveals.length; r2++) io.observe(reveals[r2]);
  }

  // Leaving the page: cancel the pending safety-net reset
  window.addEventListener("pagehide", function () {
    clearTimeout(resetTimer);
  });

  // Reset when coming back with the browser's back button (bfcache)
  window.addEventListener("pageshow", function (e) {
    if (e.persisted) reset();
  });
})();

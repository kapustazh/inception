/* ============================================================
   M.NESTERENKO — portfolio interactions (v2)
   Scroll reveals, 'run' typewriter,
   live Stuttgart clock. Vanilla JS, no dependencies.
   ============================================================ */
(function () {
  'use strict';

  var reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var reveals = Array.prototype.slice.call(document.querySelectorAll('[data-reveal]'));

  /* ---------- Load-in gate: start hero animations only once fonts are in,
     so the name doesn't rise in fallback Arial and snap to Archivo. ---------- */
  var started = false;
  var start = function () {
    if (started) return;
    started = true;
    document.documentElement.classList.add('ready');
    initReveals();
  };
  if (!reduced && document.fonts && document.fonts.ready) {
    document.fonts.ready.then(start);
    setTimeout(start, 1000); /* failsafe: never hold the page hostage to fonts */
  } else {
    start();
  }

  /* ---------- Scroll reveals ---------- */

  function revealAll() {
    reveals.forEach(function (el) { el.classList.add('revealed'); });
  }

  function initReveals() {
    if (reduced || !('IntersectionObserver' in window)) {
      revealAll();
      return;
    }
    var i = 0;
    var show = function (el, stagger) {
      var delay = stagger ? (i++ % 3) * 90 : 0;
      setTimeout(function () { el.classList.add('revealed'); }, delay);
    };
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          show(entry.target, true);
          io.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15 });

    reveals.forEach(function (el) {
      var r = el.getBoundingClientRect();
      var inView = r.top < window.innerHeight && r.bottom > 0;
      if (inView) {
        requestAnimationFrame(function () { show(el, true); });
      } else {
        io.observe(el);
      }
    });

    /* Failsafe: never leave content hidden */
    setTimeout(function () {
      reveals.forEach(function (el) {
        if (!el.classList.contains('revealed')) el.classList.add('revealed');
      });
    }, 2000);
  }

  /* ---------- 'run' mark typewriter on first view ---------- */
  var mark = document.querySelector('[data-run-mark]');
  if (mark && !reduced) {
    var played = false;
    var playMark = function () {
      if (played) return;
      played = true;
      var word = 'run';
      var n = 0;
      mark.textContent = '\u00a0';
      var step = function () {
        n++;
        mark.textContent = word.slice(0, n) + (n < word.length ? '_' : '');
        if (n < word.length) setTimeout(step, 140);
      };
      setTimeout(step, 250);
    };
    if ('IntersectionObserver' in window) {
      var mio = new IntersectionObserver(function (entries) {
        entries.forEach(function (en) {
          if (en.isIntersecting) { playMark(); mio.disconnect(); }
        });
      }, { threshold: 0.4 });
      mio.observe(mark);
      setTimeout(playMark, 2500); /* failsafe */
    } else {
      playMark();
    }
  }

  /* ---------- Live Stuttgart clock ---------- */
  var clockEl = document.getElementById('clock');
  if (clockEl) {
    var fmt;
    try {
      fmt = new Intl.DateTimeFormat('en-GB', {
        hour: '2-digit', minute: '2-digit', second: '2-digit',
        hour12: false, timeZone: 'Europe/Berlin'
      });
    } catch (e) { fmt = null; }
    var tick = function () {
      if (fmt) clockEl.textContent = fmt.format(new Date()) + ' CET';
    };
    tick();
    setInterval(tick, 1000);
  }
})();

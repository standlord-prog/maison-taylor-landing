/* Maison Taylor — edit mode: point at an element, say what to change, copy the list for Claude.
   Turn on with ?edit in the address, off with ?edit=off or the "Выйти" button. Notes live in this browser only. */
(function () {
  var KEY = 'mt_edit_notes', ON = 'mt_edit';
  var notes = [];
  try { notes = JSON.parse(localStorage.getItem(KEY) || '[]'); } catch (e) {}
  function save() { try { localStorage.setItem(KEY, JSON.stringify(notes)); } catch (e) {} }

  var css = document.createElement('style');
  css.textContent =
    '.mtpk-hover{outline:2px dashed #e0457b!important;outline-offset:2px!important;cursor:crosshair!important}' +
    '.mtpk-sel{outline:3px solid #e0457b!important;outline-offset:2px!important}' +
    '.mtpk-ui,.mtpk-ui *{all:revert;box-sizing:border-box;font:14px/1.35 -apple-system,system-ui,sans-serif;color:#111}' +
    '.mtpk-bar{position:fixed;left:50%;bottom:12px;transform:translateX(-50%);z-index:2147483646;background:#111;border-radius:14px;padding:8px;display:flex;gap:6px;align-items:center;box-shadow:0 6px 24px rgba(0,0,0,.3);max-width:calc(100vw - 24px);flex-wrap:wrap;justify-content:center}' +
    '.mtpk-bar span{color:#fff;padding:0 6px}' +
    '.mtpk-ui button{border:0;border-radius:10px;padding:8px 12px;background:#fff;cursor:pointer;font-weight:600}' +
    '.mtpk-ui button.pri{background:#e0457b;color:#fff}' +
    '.mtpk-pop{position:fixed;z-index:2147483647;background:#fff;border-radius:12px;padding:10px;width:min(320px,calc(100vw - 24px));box-shadow:0 8px 30px rgba(0,0,0,.25)}' +
    '.mtpk-pop b{display:block;font-size:12px;color:#666;margin-bottom:6px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}' +
    '.mtpk-pop textarea{display:block;width:100%;min-height:72px;border:1px solid #ccc;border-radius:8px;padding:8px;margin-bottom:8px;resize:vertical}' +
    '.mtpk-pin{position:absolute;z-index:2147483645;background:#e0457b;color:#fff!important;border-radius:999px;min-width:22px;height:22px;padding:0 6px;font:700 12px/22px system-ui!important;text-align:center;pointer-events:none}' +
    '.mtpk-out{position:fixed;inset:12px;z-index:2147483647;background:#fff;border-radius:12px;padding:12px;display:flex;flex-direction:column;gap:8px;box-shadow:0 8px 30px rgba(0,0,0,.3)}' +
    '.mtpk-out textarea{flex:1;width:100%;border:1px solid #ccc;border-radius:8px;padding:8px;font:13px/1.4 ui-monospace,monospace}';
  document.head.appendChild(css);

  function selector(el) {
    var parts = [];
    while (el && el.nodeType === 1 && el !== document.body) {
      if (el.id) { parts.unshift('#' + el.id); break; }
      var tag = el.tagName.toLowerCase(), i = 1, s = el;
      while ((s = s.previousElementSibling)) if (s.tagName === el.tagName) i++;
      var cls = (el.getAttribute('class') || '').split(/\s+/).filter(function (c) { return c && c.indexOf('mtpk-') !== 0; })[0];
      parts.unshift(tag + (cls ? '.' + cls : '') + (i > 1 ? ':nth-of-type(' + i + ')' : ''));
      el = el.parentElement;
    }
    return parts.join(' > ');
  }
  function describe(el) {
    var tag = el.tagName.toLowerCase();
    if (tag === 'img') return 'картинка ' + (el.getAttribute('src') || '');
    if (tag === 'video') return 'видео ' + (el.getAttribute('src') || (el.querySelector('source') || {}).src || '');
    var t = (el.innerText || el.textContent || '').replace(/\s+/g, ' ').trim();
    return '<' + tag + '> ' + (t ? '«' + (t.length > 80 ? t.slice(0, 80) + '…' : t) + '»' : '(без текста)');
  }
  function mine(el) { return el && el.closest && el.closest('.mtpk-ui'); }

  var picking = true, hovered = null, pop = null, pins = [];
  var bar = document.createElement('div');
  bar.className = 'mtpk-ui mtpk-bar';
  document.body.appendChild(bar);

  function drawBar() {
    bar.innerHTML = '';
    var label = document.createElement('span');
    label.textContent = picking ? 'Нажми на элемент' : 'Пауза: сайт работает как обычно';
    bar.appendChild(label);
    btn(picking ? 'Пауза' : 'Выбирать', function () { picking = !picking; clearHover(); drawBar(); });
    if (notes.length) {
      btn('Скопировать для Claude (' + notes.length + ')', copyAll, 'pri');
      btn('Очистить', function () { if (confirm('Удалить все заметки?')) { notes = []; save(); drawPins(); drawBar(); } });
    }
    btn('Выйти', function () { try { localStorage.removeItem(ON); } catch (e) {} location.href = location.pathname; });
  }
  function btn(text, fn, cls) {
    var b = document.createElement('button');
    b.textContent = text; if (cls) b.className = cls;
    b.addEventListener('click', function (e) { e.preventDefault(); e.stopPropagation(); fn(); });
    bar.appendChild(b);
    return b;
  }

  function drawPins() {
    pins.forEach(function (p) { p.remove(); }); pins = [];
    notes.forEach(function (n, i) {
      if (n.page !== location.pathname) return;
      var el; try { el = document.querySelector(n.sel); } catch (e) {}
      if (!el) return;
      var r = el.getBoundingClientRect(), p = document.createElement('div');
      p.className = 'mtpk-ui mtpk-pin'; p.textContent = i + 1;
      p.style.left = (r.left + window.scrollX - 8) + 'px'; p.style.top = (r.top + window.scrollY - 8) + 'px';
      document.body.appendChild(p); pins.push(p);
    });
  }

  function clearHover() { if (hovered) hovered.classList.remove('mtpk-hover'); hovered = null; }
  document.addEventListener('mouseover', function (e) {
    if (!picking || pop || mine(e.target)) return;
    clearHover(); hovered = e.target; hovered.classList.add('mtpk-hover');
  }, true);

  function block(e) { if (picking && !mine(e.target)) { e.preventDefault(); e.stopPropagation(); } }
  ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'submit'].forEach(function (t) { document.addEventListener(t, block, true); });
  document.addEventListener('click', function (e) {
    if (!picking || mine(e.target)) return;
    e.preventDefault(); e.stopPropagation();
    if (pop) return closePop();
    open(e.target);
  }, true);

  function open(el) {
    clearHover();
    el.classList.add('mtpk-sel');
    pop = document.createElement('div');
    pop.className = 'mtpk-ui mtpk-pop';
    var head = document.createElement('b'); head.textContent = describe(el);
    var ta = document.createElement('textarea'); ta.placeholder = 'Что тут поправить?';
    var row = document.createElement('div');
    var up = document.createElement('button'); up.textContent = '↑ Родитель';
    up.title = 'Выбрать блок побольше';
    var ok = document.createElement('button'); ok.textContent = 'Добавить'; ok.className = 'pri';
    var no = document.createElement('button'); no.textContent = 'Отмена';
    row.style.cssText = 'display:flex;gap:6px;justify-content:flex-end';
    row.appendChild(up); row.appendChild(no); row.appendChild(ok);
    pop.appendChild(head); pop.appendChild(ta); pop.appendChild(row);
    document.body.appendChild(pop);
    var r = el.getBoundingClientRect(), h = pop.offsetHeight, w = pop.offsetWidth;
    var top = r.bottom + 8 + h > innerHeight ? Math.max(8, r.top - h - 8) : r.bottom + 8;
    pop.style.top = Math.min(top, innerHeight - h - 70) + 'px';
    pop.style.left = Math.max(12, Math.min(r.left, innerWidth - w - 12)) + 'px';
    ta.focus();
    pop._el = el;
    up.onclick = function (e) { e.stopPropagation(); var p = el.parentElement; if (p && p !== document.body) { var t = ta.value; closePop(); open(p); pop.querySelector('textarea').value = t; } };
    no.onclick = function (e) { e.stopPropagation(); closePop(); };
    ok.onclick = function (e) {
      e.stopPropagation();
      var text = ta.value.trim(); if (!text) return ta.focus();
      notes.push({ page: location.pathname, sel: selector(el), what: describe(el), text: text });
      save(); closePop(); drawPins(); drawBar();
    };
    ta.addEventListener('keydown', function (e) { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) ok.click(); if (e.key === 'Escape') closePop(); });
  }
  function closePop() { if (!pop) return; pop._el.classList.remove('mtpk-sel'); pop.remove(); pop = null; }

  function copyAll() {
    var text = 'Правки сайта maison-taylor.com:\n\n' + notes.map(function (n, i) {
      return (i + 1) + ') ' + (n.page === '/' ? '/index.html' : n.page) + ' — ' + n.what + '\n   селектор: ' + n.sel + '\n   → ' + n.text;
    }).join('\n\n');
    function shown() {
      var out = document.createElement('div'); out.className = 'mtpk-ui mtpk-out';
      var t = document.createElement('div'); t.textContent = 'Скопируй этот текст и вставь в чат с Claude:';
      var ta = document.createElement('textarea'); ta.value = text; ta.readOnly = true;
      var close = document.createElement('button'); close.textContent = 'Закрыть';
      close.onclick = function (e) { e.stopPropagation(); out.remove(); };
      out.appendChild(t); out.appendChild(ta); out.appendChild(close);
      document.body.appendChild(out); ta.focus(); ta.select();
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        var b = bar.querySelector('.pri'); b.textContent = 'Скопировано ✓ вставь в чат';
        setTimeout(drawBar, 2500);
      }, shown);
    } else shown();
  }

  drawBar(); drawPins();
  window.addEventListener('resize', drawPins);
  window.addEventListener('load', drawPins);
})();

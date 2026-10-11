/* Maison Taylor — connection to the server (Supabase). Shared by signin, studio and ops pages. */
(function () {
  var cfg = window.MT_CONFIG || {};
  var ready = !!(cfg.supabaseUrl && cfg.supabaseAnonKey && window.supabase);
  var sb = ready ? window.supabase.createClient(cfg.supabaseUrl, cfg.supabaseAnonKey) : null;

  function el(tag, attrs, kids) {
    var e = document.createElement(tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === 'text') e.textContent = attrs[k];
      else if (k.slice(0, 2) === 'on') e.addEventListener(k.slice(2), attrs[k]);
      else e.setAttribute(k, attrs[k]);
    });
    (kids || []).forEach(function (c) { if (c) e.appendChild(typeof c === 'string' ? document.createTextNode(c) : c); });
    return e;
  }

  // Signed links to private files, cached for the page's life.
  var linkCache = {};
  function fileUrl(bucket, path) {
    var key = bucket + ':' + path;
    if (linkCache[key]) return Promise.resolve(linkCache[key]);
    return sb.storage.from(bucket).createSignedUrl(path, 3600).then(function (r) {
      if (r.error) throw r.error;
      linkCache[key] = r.data.signedUrl;
      return linkCache[key];
    });
  }

  function safeName(name) {
    var ext = (name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '');
    return Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8) + '.' + ext;
  }

  function must(r) { if (r.error) throw r.error; return r.data; }

  function requireUser(goTo) {
    return sb.auth.getSession().then(function (r) {
      var s = r.data && r.data.session;
      if (!s) { location.href = goTo || 'signin.html'; return null; }
      return s.user;
    });
  }

  window.MTLive = {
    ready: ready, sb: sb, el: el, fileUrl: fileUrl, safeName: safeName, must: must, requireUser: requireUser,
    angles: ['Front', 'Three-quarter', 'Side', 'Back', 'In motion', 'Full look', 'No model', 'Close-up']
  };
})();

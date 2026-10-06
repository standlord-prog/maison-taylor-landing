/* Maison Taylor — shared header, footer, carousel mock */
(function () {
  var page = document.body.getAttribute('data-page') || '';
  var links = [
    ['index.html', 'Carousels', 'home'],
    ['photos.html', 'Catalog photos', 'photos'],
    ['examples.html', 'Examples', 'examples'],
    ['pricing.html', 'Pricing', 'pricing'],
    ['signin.html', 'Sign in', 'signin'],
    ['free.html', 'Free carousel', 'free', 'nav-cta']
  ];
  var nav = document.getElementById('mt-nav');
  if (nav) {
    nav.outerHTML =
      '<input type="checkbox" id="nav-toggle" class="nav-toggle" aria-hidden="true">' +
      '<nav class="top">' +
      '<a href="index.html" class="logo-link" aria-label="Maison Taylor — home"><div class="logo"><span class="maison">Maison</span><span class="taylor">Taylor</span></div></a>' +
      '<label for="nav-toggle" class="nav-burger" aria-label="Menu" role="button" tabindex="0"><span></span><span></span><span></span></label>' +
      '<div class="nav-links">' +
      links.map(function (l) {
        return '<a href="' + l[0] + '" class="' + (l[3] || '') + (page === l[2] ? ' on' : '') + '">' + l[1] + '</a>';
      }).join('') +
      '</div></nav>';
  }
  var foot = document.getElementById('mt-footer');
  if (foot) {
    foot.outerHTML =
      '<footer class="footer"><div class="footer-grid">' +
      '<div><div class="footer-brand">Maison Taylor</div><p class="footer-tag">Instagram carousels and catalog photos that sell clothes, made in your brand’s style.</p></div>' +
      '<div><h4>Product</h4><a href="index.html">Carousels</a><a href="photos.html">Catalog photos</a><a href="free.html">Free carousel</a><a href="examples.html">Examples</a><a href="pricing.html">Pricing</a></div>' +
      '<div><h4>For brands</h4><a href="for-streetwear.html">Streetwear</a><a href="for-streetwear.html">Womenswear</a><a href="for-streetwear.html">Activewear</a><a href="for-streetwear.html">Denim</a></div>' +
      '<div><h4>Company</h4><a href="mailto:hello@maison-taylor.com">Contact</a><a href="/privacy.html">Privacy</a><a href="/terms.html">Terms</a></div>' +
      '</div><div class="footer-bottom"><span>© 2026 Maison Taylor. All rights reserved.</span><span>Made for independent fashion brands.</span></div></footer>';
  }
  var t = document.getElementById('nav-toggle');
  if (t) document.querySelectorAll('.nav-links a').forEach(function (a) { a.addEventListener('click', function () { t.checked = false; }); });

  // Fade-in like the main site
  if ('IntersectionObserver' in window) {
    var io = new IntersectionObserver(function (es) {
      es.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('visible'); io.unobserve(e.target); } });
    }, { threshold: 0.08 });
    document.querySelectorAll('.section').forEach(function (el) { el.classList.add('fade-in'); io.observe(el); });
  }
})();

/* Carousel mock: MT.carousel(el, {brand, theme, slides}) */
window.MT = {
  shotList: [
    ['Front', '50% 18%', ''], ['Three-quarter', '38% 22%', ''], ['Side', '62% 22%', 'scaleX(-1)'], ['Back', '50% 30%', 'scaleX(-1)'],
    ['In motion', '45% 55%', ''], ['Full look', '55% 70%', ''], ['No model', '', '', 'flat'], ['Close-up', '48% 38%', '', 'close']
  ],
  shots: function (el, n) {
    el.innerHTML = MT.shotList.slice(0, n || 8).map(function (s, i) {
      return '<div class="shot ' + (s[3] || '') + '" style="' + (s[1] ? 'background-position:' + s[1] + ';' : '') + (s[2] ? 'transform:' + s[2] + ';' : '') + '"><span' + (s[2] === 'scaleX(-1)' ? ' style="transform:scaleX(-1)"' : '') + '><b>' + (i + 1) + '</b>' + s[0] + '</span></div>';
    }).join('');
  },
  sample: {
    brand: 'sample.studio',
    slides: [
      { kind: 'photo', pos: '50% 22%', tag: 'New · The Linen Day Dress', big: 'The dress that survives a 9-hour day.', sub: 'Swipe for fit, fabric and what to wear it with →' },
      { kind: 'photo', pos: '30% 40%', price: '$148', big: 'The Linen Day Dress', sub: 'Midi length · relaxed waist · 6 colors' },
      { kind: 'paper', k: 'Fit verdict', v: 'True to size. Relaxed on purpose.', rows: [['Ana · 5’7” · waist 27”', 'wearing S'], ['Hem lands', 'mid-calf'], ['Between sizes?', 'size down']] },
      { kind: 'photo', pos: '70% 60%', big: 'Not see-through. Fully lined.', sub: '100% European linen · 185 GSM' },
      { kind: 'photo', pos: '50% 80%', big: 'Office. Dinner. Weekend.', sub: 'One dress, three looks →' },
      { kind: 'paper', k: 'What buyers say', v: '“Finally, linen that doesn’t look slept in.”', rows: [['★ 4.8 · 212 reviews', 'on our site'], ['84% say', 'true to size']] },
      { kind: 'ink', k: 'Fit & Fabric', v: 'Save this before you order.', rows: [['Fabric', '100% linen, lined'], ['Care', 'machine wash cold'], ['Stretch', 'none'], ['Pockets', 'yes, both sides']] },
      { kind: 'ink', k: 'The Linen Day Dress', v: '$148 · XS–XXL · 6 colors', rows: [['Free US shipping', 'over $100'], ['Free 30-day returns', 'refund to card'], ['Tap the tag to shop', '→']] }
    ]
  },
  carousel: function (el, data) {
    data = data || MT.sample;
    var n = data.slides.length;
    var html = '<div class="ig ' + (data.theme || '') + '"><div class="ig-head"><div class="ig-ava" style="background-image:url(../assets/lea-hero-poster.jpg)"></div><div><div class="ig-name">' + (data.brand || 'your.brand') + '</div><div class="ig-sub">Sponsored · Shop</div></div></div><div class="ig-stage">' + (n > 1 ? '<span class="ig-count">1/' + n + '</span><button class="ig-arrow prev" aria-label="Previous">‹</button><button class="ig-arrow next" aria-label="Next">›</button>' : '') + '<div class="ig-track">';
    data.slides.forEach(function (s) {
      if (s.kind === 'photo') {
        html += '<div class="slide"><div class="ph" style="background-position:' + (s.pos || 'center') + '"></div><div class="shade"></div>' +
          (s.tag ? '<div class="tag">' + s.tag + '</div>' : '') + (s.price ? '<div class="price">' + s.price + '</div>' : '') +
          '<div class="txt"><div class="big">' + s.big + '</div>' + (s.sub ? '<div class="sub">' + s.sub + '</div>' : '') + '</div></div>';
      } else {
        html += '<div class="slide paper ' + (s.kind === 'ink' ? 'ink' : '') + '"><div class="inner"><div><div class="k">' + s.k + '</div><div class="v" style="margin-top:.6rem">' + s.v + '</div></div><div>' +
          (s.rows || []).map(function (r) { return '<div class="row"><span>' + r[0] + '</span><b>' + r[1] + '</b></div>'; }).join('') + '</div></div></div>';
      }
    });
    html += '</div></div><div class="ig-foot">' + (n < 2 ? '' : data.slides.map(function (_, i) { return '<i class="' + (i ? '' : 'on') + '"></i>'; }).join('')) + '</div></div>';
    el.innerHTML = html;
    if (n < 2) return;
    var track = el.querySelector('.ig-track'), dots = el.querySelectorAll('.ig-foot i'), cnt = el.querySelector('.ig-count');
    function cur() { return Math.round(track.scrollLeft / track.clientWidth); }
    track.addEventListener('scroll', function () {
      var i = cur(); cnt.textContent = (i + 1) + '/' + n;
      dots.forEach(function (d, j) { d.classList.toggle('on', i === j); });
    });
    el.querySelector('.prev').onclick = function () { track.scrollTo({ left: (cur() - 1) * track.clientWidth, behavior: 'smooth' }); };
    el.querySelector('.next').onclick = function () { track.scrollTo({ left: (cur() + 1) * track.clientWidth, behavior: 'smooth' }); };
  }
};

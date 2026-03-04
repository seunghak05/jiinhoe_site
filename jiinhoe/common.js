/* 지인회 공통 스크립트 */
(function () {
  /* 스크롤 프로그레스바 */
  const pb = document.getElementById('pb');
  if (pb) {
    window.addEventListener('scroll', function () {
      const h = document.documentElement;
      pb.style.width = (h.scrollTop / (h.scrollHeight - h.clientHeight) * 100) + '%';
    }, { passive: true });
  }

  /* 모바일 메뉴 */
  const nh = document.getElementById('nh');
  const mobNav = document.getElementById('mob-nav');
  if (nh && mobNav) {
    nh.addEventListener('click', function () {
      mobNav.classList.toggle('open');
    });
    mobNav.querySelectorAll('a').forEach(function (a) {
      a.addEventListener('click', function () {
        mobNav.classList.remove('open');
      });
    });
  }

  /* 저작권 연도 자동 업데이트 */
  const ftCopy = document.querySelector('.ft-copy');
  if (ftCopy) {
    ftCopy.textContent = '© ' + new Date().getFullYear() + ' 지인회 (志人會). All rights reserved.';
  }

  /* 스크롤 reveal */
  const ro = new IntersectionObserver(function (entries) {
    entries.forEach(function (e) {
      if (e.isIntersecting) {
        e.target.classList.add('in');
        ro.unobserve(e.target);
      }
    });
  }, { threshold: 0.08 });
  document.querySelectorAll('.rv').forEach(function (el) {
    ro.observe(el);
  });
})();

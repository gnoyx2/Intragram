/* ==========================================================================
   Intragram Landing Page — Language, Theme & Navigation Script
   Zero External Dependencies · Zero Cookies · Zero Web Storage
   ========================================================================== */
(function () {
  'use strict';

  const TITLES = {
    ko: 'Intragram: 서버도 계정도 없는 로컬 네트워크 메신저',
    en: 'Intragram: Local-Network Messenger Without Servers',
  };

  const liveRegion = document.getElementById('live-status');
  function announce(msgKo, msgEn) {
    if (!liveRegion) return;
    liveRegion.textContent = document.documentElement.lang === 'ko' ? msgKo : msgEn;
  }

  /* --- 1. Bilingual Switcher (KO / EN) --- */
  const langButtons = document.querySelectorAll('[data-set-lang]');
  const menuToggle = document.getElementById('menu-toggle');
  const mobileSheet = document.getElementById('mobile-sheet');
  function syncToggleLabel(isOpen) {
    if (!menuToggle) return;
    const isKo = document.documentElement.lang !== 'en';
    const label = isOpen
      ? menuToggle.getAttribute(isKo ? 'data-aria-close-ko' : 'data-aria-close-en')
      : menuToggle.getAttribute(isKo ? 'data-aria-ko' : 'data-aria-en');
    if (label) menuToggle.setAttribute('aria-label', label);
  }

  function updateWebLinks() {
    document.querySelectorAll('[data-web-link]').forEach((link) => {
      const url = new URL(link.href);
      url.searchParams.set('lang', document.documentElement.lang);
      const theme = document.documentElement.getAttribute('data-theme');
      if (theme) url.searchParams.set('theme', theme);
      else url.searchParams.delete('theme');
      link.href = url.href;
    });
  }

  function applyLang(lang, announceChange) {
    const normalized = lang === 'en' ? 'en' : 'ko';
    document.documentElement.lang = normalized;
    document.title = TITLES[normalized];
    updateWebLinks();

    langButtons.forEach((btn) => {
      const active = btn.getAttribute('data-set-lang') === normalized;
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });

    document.querySelectorAll('[data-aria-ko][data-aria-en]').forEach((el) => {
      el.setAttribute(
        'aria-label',
        normalized === 'ko'
          ? el.getAttribute('data-aria-ko')
          : el.getAttribute('data-aria-en')
      );
    });

    syncToggleLabel(Boolean(mobileSheet && !mobileSheet.hidden));

    if (announceChange) {
      try {
        const url = new URL(window.location.href);
        url.searchParams.set('lang', normalized);
        window.history.replaceState(null, '', url.toString());
      } catch (_) {}
      announce('한국어로 전환했습니다.', 'Switched language to English.');
    }
  }

  langButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      applyLang(btn.getAttribute('data-set-lang'), true);
    });
  });

  /* --- 2. Theme Switcher (System / Light / Dark) --- */
  const themeButtons = document.querySelectorAll('[data-set-theme]');
  function applyTheme(mode, announceChange) {
    const root = document.documentElement;
    if (mode === 'light' || mode === 'dark') {
      root.setAttribute('data-theme', mode);
    } else {
      root.removeAttribute('data-theme');
      mode = 'system';
    }
    themeButtons.forEach((btn) => {
      const active = btn.getAttribute('data-set-theme') === mode;
      btn.setAttribute('aria-pressed', active ? 'true' : 'false');
    });
    updateWebLinks();
    if (announceChange) {
      const labels = {
        system: ['시스템 테마를 따릅니다.', 'Following system theme.'],
        light: ['라이트 테마로 전환했습니다.', 'Switched to light theme.'],
        dark: ['다크 테마로 전환했습니다.', 'Switched to dark theme.'],
      };
      const pair = labels[mode] || labels.system;
      announce(pair[0], pair[1]);
    }
  }

  themeButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      applyTheme(btn.getAttribute('data-set-theme'), true);
    });
  });

  /* --- 3. Mobile Menu Sheet --- */
  function closeSheet(returnFocus) {
    if (!menuToggle || !mobileSheet || mobileSheet.hidden) return;
    mobileSheet.hidden = true;
    document.documentElement.classList.remove('sheet-open');
    menuToggle.setAttribute('aria-expanded', 'false');
    syncToggleLabel(false);
    if (returnFocus) menuToggle.focus();
  }

  function openSheet() {
    if (!menuToggle || !mobileSheet || !mobileSheet.hidden) return;
    mobileSheet.hidden = false;
    document.documentElement.classList.add('sheet-open');
    menuToggle.setAttribute('aria-expanded', 'true');
    syncToggleLabel(true);
  }

  if (menuToggle && mobileSheet) {
    menuToggle.addEventListener('click', () => {
      if (mobileSheet.hidden) openSheet();
      else closeSheet(false);
    });

    mobileSheet.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => closeSheet(false));
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !mobileSheet.hidden) {
        closeSheet(true);
      }
    });

    const desktopMedia = window.matchMedia('(min-width: 64rem)');
    desktopMedia.addEventListener('change', (e) => {
      if (e.matches && !mobileSheet.hidden) closeSheet(false);
    });
  }

  /* --- 4. Client OS Detection (Highlights Matching Card in #install) --- */
  function detectClientOs() {
    const ua = (navigator.userAgent || '').toLowerCase();
    const platform = (
      (navigator.userAgentData && navigator.userAgentData.platform) ||
      navigator.platform ||
      ''
    ).toLowerCase();

    if (/android/.test(ua)) return 'android';
    if (/iphone|ipad|ipod/.test(ua) || (platform === 'macintel' && navigator.maxTouchPoints > 1)) {
      return 'ios';
    }
    if (/mac/.test(platform) || /mac os x/.test(ua)) return 'macos';
    if (/win/.test(platform) || /windows/.test(ua)) return 'windows';
    if (/linux/.test(platform) || /linux/.test(ua)) return 'linux';
    return null;
  }

  const detectedOs = detectClientOs();
  if (detectedOs) {
    const card = document.querySelector(`.dl-card[data-os="${detectedOs}"]`);
    if (card) {
      card.setAttribute('data-detected', 'true');
      const cta = card.querySelector('.btn');
      if (cta) {
        cta.classList.remove('btn--secondary');
        cta.classList.add('btn--primary');
      }
    }
  }

  /* --- 5. Active-Section Nav Indicator (Desktop Bar + Mobile Sheet) --- */
  const allSectionLinks = Array.from(
    document.querySelectorAll('.nav__links .nav__link, .sheet-links a')
  );
  if ('IntersectionObserver' in window && allSectionLinks.length) {
    const map = new Map();
    allSectionLinks.forEach((a) => {
      const id = (a.getAttribute('href') || '').replace(/^#/, '');
      const sec = id ? document.getElementById(id) : null;
      if (!sec) return;
      if (!map.has(sec)) map.set(sec, []);
      map.get(sec).push(a);
    });
    const topSection = document.getElementById('top');
    const navObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (!entry.isIntersecting) return;
          allSectionLinks.forEach((a) => a.removeAttribute('aria-current'));
          const matches = map.get(entry.target);
          if (matches) {
            matches.forEach((a) => a.setAttribute('aria-current', 'page'));
          }
        });
      },
      { rootMargin: '-35% 0px -55% 0px' }
    );
    if (topSection && !map.has(topSection)) navObserver.observe(topSection);
    map.forEach((_, sec) => navObserver.observe(sec));
  }

  /* Sync initial button states with inline head bootstrap */
  applyLang(document.documentElement.lang || 'ko', false);
  applyTheme(document.documentElement.getAttribute('data-theme') || 'system', false);
})();

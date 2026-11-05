/* ==========================================================================
   Intragram Landing Page — Progressive Enhancement & Interactive Layer (v2)
   Zero External Dependencies · Zero Cookies · Zero Web Storage
   Compliant with Leonxlnx/taste-skill motion.md & Intragram Privacy Policy
   ========================================================================== */
(function () {
  'use strict';

  const TITLES = {
    ko: 'Intragram: 서버도 계정도 없는 로컬 네트워크 P2P 메신저',
    en: 'Intragram: Local-Network P2P Messenger Without Servers',
  };

  const OS_HINTS = {
    macos: {
      ko: '현재 기기(macOS Universal)용 DMG·ZIP 준비됨 · 눌러서 상태 전환',
      en: 'Detected macOS Universal (DMG/ZIP ready) · Click to cycle status',
    },
    windows: {
      ko: '현재 기기(Windows x64)용 포터블 ZIP 준비됨 · 눌러서 상태 전환',
      en: 'Detected Windows x64 portable ZIP · Click to cycle status',
    },
    android: {
      ko: '현재 기기(Android 7.0+)용 통합 APK 준비됨 · 눌러서 상태 전환',
      en: 'Detected Android 7.0+ universal APK · Click to cycle status',
    },
    linux: {
      ko: '현재 기기(Linux x64)용 TAR.GZ 번들 준비됨 · 눌러서 상태 전환',
      en: 'Detected Linux x64 TAR.GZ bundle · Click to cycle status',
    },
    ios: {
      ko: '현재 기기(iOS · iPadOS) 미서명 IPA 안내 · 눌러서 상태 전환',
      en: 'Detected iOS / iPadOS install guide · Click to cycle status',
    },
  };

  const liveRegion = document.getElementById('live-status');
  function announce(msgKo, msgEn) {
    if (!liveRegion) return;
    liveRegion.textContent = document.documentElement.lang === 'ko' ? msgKo : msgEn;
  }

  /* --- 1. Bilingual Switcher (KO / EN) --- */
  const langButtons = document.querySelectorAll('[data-set-lang]');
  function applyLang(lang, announceChange) {
    const normalized = lang === 'en' ? 'en' : 'ko';
    document.documentElement.lang = normalized;
    document.title = TITLES[normalized];

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

  /* --- 3. Full-Screen Mobile Menu Sheet --- */
  const menuToggle = document.getElementById('menu-toggle');
  const mobileSheet = document.getElementById('mobile-sheet');
  function closeSheet(returnFocus) {
    if (!menuToggle || !mobileSheet || mobileSheet.hidden) return;
    mobileSheet.hidden = true;
    menuToggle.setAttribute('aria-expanded', 'false');
    if (returnFocus) menuToggle.focus();
  }

  if (menuToggle && mobileSheet) {
    menuToggle.addEventListener('click', () => {
      const willOpen = mobileSheet.hidden;
      mobileSheet.hidden = !willOpen;
      menuToggle.setAttribute('aria-expanded', willOpen ? 'true' : 'false');
    });

    mobileSheet.querySelectorAll('a').forEach((link) => {
      link.addEventListener('click', () => closeSheet(false));
    });

    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && !mobileSheet.hidden) {
        closeSheet(true);
      }
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
  if (detectedOs && OS_HINTS[detectedOs]) {
    const card = document.querySelector(`.dl-card[data-os="${detectedOs}"]`);
    if (card) card.setAttribute('data-detected', 'true');
    const hintKo = document.getElementById('hero-os-hint-ko');
    const hintEn = document.getElementById('hero-os-hint-en');
    if (hintKo) hintKo.textContent = OS_HINTS[detectedOs].ko;
    if (hintEn) hintEn.textContent = OS_HINTS[detectedOs].en;
  }

  /* --- 5. Interactive Hero Carrier Pigeon Courier Companion --- */
  const courierStates = [
    {
      ko: '클라우드 전송 0 B · 같은 공유기 안에서만 봉인 전달',
      en: '0 B sent to cloud · Sealed delivery inside your router',
    },
    {
      ko: 'mDNS _intragram._tcp · 20초 주기로 주변 피어 자동 탐색',
      en: 'mDNS _intragram._tcp · Refreshes nearby peers every 20s',
    },
    {
      ko: '6자리 SAS 482 917 · 양쪽 화면 코드 대조로 중계 공격 차단',
      en: '6-digit SAS 482 917 · Verbal check stops relay attacks',
    },
    {
      ko: 'RAM 전용 세션 · 앱을 닫으면 디스크 흔적 없이 소멸',
      en: 'RAM-only session · Vanishes cleanly when you close the app',
    },
  ];
  let courierIndex = 0;
  const courierBtn = document.getElementById('mascot-courier-btn');
  const courierKo = document.getElementById('mascot-state-ko');
  const courierEn = document.getElementById('mascot-state-en');
  if (courierBtn && courierKo && courierEn) {
    courierBtn.addEventListener('click', () => {
      courierIndex = (courierIndex + 1) % courierStates.length;
      const item = courierStates[courierIndex];
      courierKo.textContent = item.ko;
      courierEn.textContent = item.en;
      announce(item.ko, item.en);
    });
  }

  /* --- 6. Accessible Product Window Tabs (Click & Arrow Keys Only) --- */
  const tabs = Array.from(document.querySelectorAll('.demo-tab[role="tab"]'));
  const panels = Array.from(document.querySelectorAll('.demo-panel[role="tabpanel"]'));

  function activateTab(targetTab, moveFocus) {
    tabs.forEach((tab) => {
      const selected = tab === targetTab;
      tab.setAttribute('aria-selected', selected ? 'true' : 'false');
      tab.tabIndex = selected ? 0 : -1;
    });
    panels.forEach((panel) => {
      panel.hidden = panel.id !== targetTab.getAttribute('aria-controls');
    });
    if (moveFocus) targetTab.focus();
    if (targetTab.id !== 'tab-chat') stopBurnTimer(false);
  }

  tabs.forEach((tab, index) => {
    tab.addEventListener('click', () => activateTab(tab, false));
    tab.addEventListener('keydown', (e) => {
      let nextIndex = null;
      if (e.key === 'ArrowRight') nextIndex = (index + 1) % tabs.length;
      if (e.key === 'ArrowLeft') nextIndex = (index - 1 + tabs.length) % tabs.length;
      if (e.key === 'Home') nextIndex = 0;
      if (e.key === 'End') nextIndex = tabs.length - 1;
      if (nextIndex !== null) {
        e.preventDefault();
        activateTab(tabs[nextIndex], true);
      }
    });
  });

  /* --- 6a. Tab 1 Controls: SAS Verify, 5s Burn Timer, Panic Wipe --- */
  const sasBadge = document.getElementById('demo-sas-badge');
  const sasBtn = document.getElementById('btn-sas-toggle');
  if (sasBadge && sasBtn) {
    sasBtn.addEventListener('click', () => {
      const next = sasBadge.getAttribute('data-verified') === 'false';
      sasBadge.setAttribute('data-verified', next ? 'true' : 'false');
      const koSpan = sasBadge.querySelector('[data-lang="ko"]');
      const enSpan = sasBadge.querySelector('[data-lang="en"]');
      if (koSpan) koSpan.textContent = next ? 'SAS 482 917 · 확인됨' : 'SAS 482 917 · 미확인';
      if (enSpan) enSpan.textContent = next ? 'SAS 482 917 · Verified' : 'SAS 482 917 · Unverified';
      announce(
        next ? '6자리 SAS 코드가 확인됨으로 변경되었습니다.' : '6자리 SAS 코드가 미확인 상태로 변경되었습니다.',
        next ? '6-digit SAS marked verified.' : '6-digit SAS marked unverified.'
      );
    });
  }

  let burnInterval = null;
  let burnSeconds = 5;
  const burnBtn = document.getElementById('btn-burn-test');
  const burnCounter = document.getElementById('demo-burn-counter');
  const burnTextKo = document.getElementById('demo-burn-text-ko');
  const burnTextEn = document.getElementById('demo-burn-text-en');

  function stopBurnTimer(resetText) {
    if (burnInterval) {
      clearInterval(burnInterval);
      burnInterval = null;
    }
    if (resetText) {
      burnSeconds = 5;
      if (burnCounter) burnCounter.textContent = '5s';
      if (burnTextKo) {
        burnTextKo.textContent =
          '테스트 장비 초기 PIN은 941820입니다. 읽은 뒤 5초 후 메모리에서 소각됩니다.';
      }
      if (burnTextEn) {
        burnTextEn.textContent =
          'Bench PIN is 941820. Burns from RAM 5 seconds after reading.';
      }
    }
  }

  if (burnBtn && burnCounter) {
    burnBtn.addEventListener('click', () => {
      const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      if (burnCounter.textContent === '0s') {
        stopBurnTimer(true);
        announce('소각 데모 메시지를 복원했습니다.', 'Restored burn demo message.');
        return;
      }
      if (burnInterval) {
        stopBurnTimer(false);
        announce('소각 타이머를 일시 정지했습니다.', 'Paused burn timer.');
        return;
      }
      if (reducedMotion) {
        burnSeconds = 0;
        burnCounter.textContent = '0s';
        if (burnTextKo) burnTextKo.textContent = '메시지 본문 참조가 메모리에서 소각되었습니다.';
        if (burnTextEn) burnTextEn.textContent = 'Message body dropped from memory.';
        announce('메시지가 메모리에서 소각되었습니다.', 'Message burned from memory.');
        return;
      }
      announce('5초 소각 카운트다운을 시작합니다.', 'Started 5-second burn timer.');
      burnInterval = setInterval(() => {
        burnSeconds -= 1;
        if (burnSeconds <= 0) {
          clearInterval(burnInterval);
          burnInterval = null;
          burnSeconds = 0;
          burnCounter.textContent = '0s';
          if (burnTextKo) {
            burnTextKo.textContent =
              '메시지 본문 참조가 메모리에서 소각되었습니다. (다시 누르면 복원)';
          }
          if (burnTextEn) {
            burnTextEn.textContent =
              'Message body dropped from RAM. (Click again to restore)';
          }
          announce('메시지가 메모리에서 소각되었습니다.', 'Message burned from memory.');
        } else {
          burnCounter.textContent = `${burnSeconds}s`;
        }
      }, 1000);
    });
  }

  document.addEventListener('visibilitychange', () => {
    if (document.hidden && burnInterval) stopBurnTimer(false);
  });

  const panicBtn = document.getElementById('btn-panic-wipe');
  const restoreBtn = document.getElementById('btn-restore-demo');
  const chatStream = document.getElementById('demo-chat-stream');
  const wipeState = document.getElementById('demo-wipe-state');
  const peerIdEl = document.getElementById('demo-peer-id');

  function randomHexId() {
    const chars = '0123456789abcdef';
    let a = '';
    let b = '';
    for (let i = 0; i < 4; i += 1) {
      a += chars[Math.floor(Math.random() * 16)];
      b += chars[Math.floor(Math.random() * 16)];
    }
    return `${a}…${b}`;
  }

  if (panicBtn && restoreBtn && chatStream && wipeState) {
    panicBtn.addEventListener('click', () => {
      stopBurnTimer(true);
      chatStream.hidden = true;
      wipeState.hidden = false;
      const nextId = randomHexId();
      if (peerIdEl) peerIdEl.textContent = `id ${nextId}`;
      const newIdSpan = document.getElementById('demo-new-id');
      if (newIdSpan) newIdSpan.textContent = nextId;
      restoreBtn.focus();
      announce(
        '긴급 소거 완료: 연결 종료, 버퍼 덮어쓰기, 새 임시 신원 발급.',
        'Panic wipe simulated: links closed, buffers overwritten, fresh identity issued.'
      );
    });

    restoreBtn.addEventListener('click', () => {
      wipeState.hidden = true;
      chatStream.hidden = false;
      panicBtn.focus();
      announce('대화 데모를 복원했습니다.', 'Restored chat demo.');
    });
  }

  /* --- 6b. Tab 3 NetworkGuard Classifier --- */
  function checkPeerEndpoint(raw) {
    const parts = raw.split(':');
    if (parts.length !== 2) return { ok: false, reason: 'format' };
    const host = parts[0];
    const port = Number(parts[1]);
    if (!Number.isInteger(port) || port < 1 || port > 65535) {
      return { ok: false, reason: 'port' };
    }
    const octets = host.split('.');
    if (octets.length !== 4) return { ok: false, reason: 'ipv4' };
    const nums = [];
    for (const part of octets) {
      if (!/^(0|[1-9][0-9]{0,2})$/.test(part)) {
        return { ok: false, reason: 'octal_or_noncanonical' };
      }
      const val = Number(part);
      if (val > 255) return { ok: false, reason: 'range' };
      nums.push(val);
    }
    if (nums.join('.') !== host) return { ok: false, reason: 'octal_or_noncanonical' };

    const isRfc1918 =
      nums[0] === 10 ||
      (nums[0] === 172 && nums[1] >= 16 && nums[1] <= 31) ||
      (nums[0] === 192 && nums[1] === 168);

    if (!isRfc1918) {
      if (nums[0] === 100 && nums[1] >= 64 && nums[1] <= 127) {
        return { ok: false, reason: 'cgnat' };
      }
      return { ok: false, reason: 'wan' };
    }
    return { ok: true, reason: 'rfc1918' };
  }

  const ipChips = document.querySelectorAll('.ip-chip[data-endpoint]');
  const verdictBox = document.getElementById('guard-verdict');
  const verdictKo = document.getElementById('guard-verdict-ko');
  const verdictEn = document.getElementById('guard-verdict-en');

  const VERDICT_MESSAGES = {
    rfc1918: {
      ko: (ep) =>
        `허용됨 (${ep}) — 정규 RFC 1918 사설 IPv4 주소입니다. WebSocket 다이얼과 X25519 핸드셰이크를 진행합니다.`,
      en: (ep) =>
        `ALLOWED (${ep}) — Canonical RFC 1918 private IPv4. Proceeding to WebSocket dial and X25519 handshake.`,
    },
    cgnat: {
      ko: (ep) =>
        `차단됨 (${ep}) — SecurityException: 통신사 CGNAT(100.64/10) 대역입니다. 사설 공유기나 핫스팟을 이용하세요.`,
      en: (ep) =>
        `REFUSED (${ep}) — SecurityException: Carrier-grade NAT (100.64/10) is not a private LAN. Use a phone hotspot.`,
    },
    wan: {
      ko: (ep) =>
        `차단됨 (${ep}) — SecurityException: 공인 인터넷(WAN) 주소입니다. Intragram 소켓은 외부 인터넷으로 나가지 않습니다.`,
      en: (ep) =>
        `REFUSED (${ep}) — SecurityException: Public WAN target blocked. Intragram sockets never leave private networks.`,
    },
    octal_or_noncanonical: {
      ko: (ep) =>
        `차단됨 (${ep}) — SecurityException: 선행 0(8진수 표기) 또는 비정규 옥텟을 원천 차단합니다.`,
      en: (ep) =>
        `REFUSED (${ep}) — SecurityException: Leading-zero octal or non-canonical octet rejected.`,
    },
  };

  ipChips.forEach((chip) => {
    chip.addEventListener('click', () => {
      const ep = chip.getAttribute('data-endpoint') || '';
      ipChips.forEach((c) => c.setAttribute('aria-pressed', c === chip ? 'true' : 'false'));
      const res = checkPeerEndpoint(ep);
      const msg = VERDICT_MESSAGES[res.reason] || VERDICT_MESSAGES.wan;
      if (verdictBox) verdictBox.setAttribute('data-allowed', res.ok ? 'true' : 'false');
      if (verdictKo) verdictKo.textContent = msg.ko(ep);
      if (verdictEn) verdictEn.textContent = msg.en(ep);
      announce(msg.ko(ep), msg.en(ep));
    });
  });

  /* --- 7. Protocol v7 Diagram Pause / Play Control (motion.md line 113) --- */
  const dgFrame = document.getElementById('protocol-diagram');
  const dgPauseBtn = document.getElementById('dg-pause-btn');
  const dgIconPause = document.getElementById('dg-icon-pause');
  const dgIconPlay = document.getElementById('dg-icon-play');
  if (dgFrame && dgPauseBtn) {
    dgPauseBtn.addEventListener('click', () => {
      const paused = dgFrame.getAttribute('data-paused') === 'true';
      const next = !paused;
      dgFrame.setAttribute('data-paused', next ? 'true' : 'false');
      dgPauseBtn.setAttribute('aria-pressed', next ? 'true' : 'false');
      if (dgIconPause) dgIconPause.hidden = next;
      if (dgIconPlay) dgIconPlay.hidden = !next;
      announce(
        next ? '프로토콜 애니메이션을 일시 정지했습니다.' : '프로토콜 애니메이션을 다시 재생합니다.',
        next ? 'Paused protocol diagram pulse.' : 'Resumed protocol diagram pulse.'
      );
    });
  }

  /* --- 8. Passive Active-Section Nav Indicator (No Scroll Listeners) --- */
  const navLinks = Array.from(document.querySelectorAll('.nav__links .nav__link'));
  if ('IntersectionObserver' in window && navLinks.length) {
    const map = new Map();
    navLinks.forEach((a) => {
      const id = (a.getAttribute('href') || '').replace(/^#/, '');
      const sec = id ? document.getElementById(id) : null;
      if (sec) map.set(sec, a);
    });
    const navObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            navLinks.forEach((a) => a.removeAttribute('aria-current'));
            const match = map.get(entry.target);
            if (match) match.setAttribute('aria-current', 'page');
          }
        });
      },
      { rootMargin: '-35% 0px -55% 0px' }
    );
    map.forEach((_, sec) => navObserver.observe(sec));
  }

  /* --- 9. CLI Snippet Copy Buttons --- */
  document.querySelectorAll('.copy-btn[data-copy-target]').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const targetId = btn.getAttribute('data-copy-target');
      const pre = targetId ? document.getElementById(targetId) : null;
      if (!pre || !navigator.clipboard) return;
      try {
        await navigator.clipboard.writeText(pre.textContent.trim());
        const koSpan = btn.querySelector('[data-lang="ko"]');
        const enSpan = btn.querySelector('[data-lang="en"]');
        const prevKo = koSpan ? koSpan.textContent : '';
        const prevEn = enSpan ? enSpan.textContent : '';
        if (koSpan) koSpan.textContent = '복사 완료';
        if (enSpan) enSpan.textContent = 'Copied';
        announce('클립보드에 명령어를 복사했습니다.', 'Copied command to clipboard.');
        setTimeout(() => {
          if (koSpan) koSpan.textContent = prevKo;
          if (enSpan) enSpan.textContent = prevEn;
        }, 1800);
      } catch (_) {
        announce('복사에 실패했습니다. 직접 선택해 복사해 주세요.', 'Copy failed. Select text manually.');
      }
    });
  });

  /* Sync initial button states with inline head bootstrap */
  applyLang(document.documentElement.lang || 'ko', false);
  applyTheme(document.documentElement.getAttribute('data-theme') || 'system', false);
})();

{{flutter_js}}
{{flutter_build_config}}

const theme = new URLSearchParams(window.location.search).get('theme');
if (theme === 'light' || theme === 'dark') document.documentElement.dataset.theme = theme;

if (window.top !== window.self) {
  // 다른 페이지의 프레임 안에서는 앱을 띄우지 않고 새 탭 링크만 보여 줌: 보이지 않는 프레임으로 클릭을 유도하지 못함.
  // 정적 호스팅은 응답 헤더(frame-ancestors)를 못 넣어서 페이지가 직접 확인함
  const loading = document.getElementById('app-loading');
  loading.querySelector('.loading-ring')?.remove();
  const open = Object.assign(document.createElement('a'), {
    href: window.location.href,
    target: '_blank',
    rel: 'noopener noreferrer',
    textContent: '새 탭에서 열기 · Open in a new tab',
  });
  loading.querySelector('p').replaceChildren(
    '다른 사이트 안에서는 열리지 않습니다. · This app does not open inside another site.',
    document.createElement('br'),
    open,
  );
} else {
  window.addEventListener('flutter-first-frame', () => {
    document.getElementById('app-loading')?.remove();
  }, { once: true });

  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: 'canvaskit/',
      fontFallbackBaseUrl: 'assets/fonts/fallback/',
    },
  });
}

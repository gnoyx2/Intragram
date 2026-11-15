const preferences = {
  lang: new Set(['ko', 'en']),
  theme: new Set(['system', 'light', 'dark']),
  mode: new Set(['portal']),
};

// Invitations and fragments never enter navigation URLs or server request logs.
export function entryTarget(href) {
  const source = new URL(href), target = new URL('./app/', source);
  for (const [name, allowed] of Object.entries(preferences)) {
    const value = source.searchParams.get(name);
    if (allowed.has(value)) target.searchParams.set(name, value);
  }
  return target;
}

if (typeof window !== 'undefined') {
  const target = entryTarget(window.location.href);
  document.getElementById('open-app').href = target.href;
  const lite = new URL('./lite.html', window.location.href); lite.search = target.search;
  document.getElementById('open-lite').href = lite.href;
  window.location.replace(target.href);
}

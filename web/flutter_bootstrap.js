{{flutter_js}}
{{flutter_build_config}}

async function clearFlutterServiceWorker() {
  if (!('serviceWorker' in navigator)) {
    return;
  }
  const registrations = await navigator.serviceWorker.getRegistrations();
  await Promise.all(registrations.map((registration) => registration.unregister()));
  if ('caches' in window) {
    const cacheNames = await caches.keys();
    await Promise.all(cacheNames.map((cacheName) => caches.delete(cacheName)));
  }
}

clearFlutterServiceWorker().finally(() => {
  _flutter.loader.load();
});

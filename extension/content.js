(() => {
  if (globalThis.__habitGateGuard) return;
  globalThis.__habitGateGuard = true;
  let expiry = 0, day = '', utcOffset = NaN, allowed = false, targeted = true, checking = false;
  const veil = document.createElement('style'); veil.textContent = 'html { visibility: hidden !important; }';
  function hide() {
    if (document.documentElement) { if (!veil.isConnected) document.documentElement.appendChild(veil); }
    else {
      const observer = new MutationObserver(() => { if (document.documentElement) { document.documentElement.appendChild(veil); observer.disconnect(); } });
      observer.observe(document, {childList: true});
    }
  }
  function localDate() {
    const d = new Date(); if (d.getHours() < 4) d.setDate(d.getDate() - 1);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
  function redirect() {
    hide(); location.replace(chrome.runtime.getURL('blocked.html') + '?target=' + location.origin + '/');
  }
  function apply(state) {
    targeted = state.targeted ?? true;
    if (!targeted) { veil.remove(); return; }
    allowed = state.allowed; expiry = Date.parse(state.snapshot?.expiresAt || '');
    day = state.snapshot?.habitDate; utcOffset = state.snapshot?.utcOffsetMinutes;
    if (allowed && Date.now() < expiry && day === localDate() && utcOffset === -new Date().getTimezoneOffset()) veil.remove();
    else redirect();
  }
  async function check() {
    if (checking) return;
    if (targeted && (!allowed || Date.now() >= expiry || day !== localDate() || utcOffset !== -new Date().getTimezoneOffset())) hide();
    checking = true;
    try { apply(await chrome.runtime.sendMessage({type: 'guard', url: location.href})); }
    catch { if (!allowed || Date.now() >= expiry) hide(); }
    finally { checking = false; }
  }
  hide(); check();
  chrome.runtime.onMessage.addListener(message => { if (message.type === 'gateState') apply(message.state); });
  for (const event of ['pageshow', 'focus']) window.addEventListener(event, check);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
  setInterval(() => {
    if (!targeted) return;
    if (allowed && (Date.now() >= expiry || day !== localDate() || utcOffset !== -new Date().getTimezoneOffset())) redirect();
  }, 1000);
})();

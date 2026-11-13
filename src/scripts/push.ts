// Turning push on and off for this device, on Me → Notifications (NOTIF-20). The browser makes a
// push subscription with FABA's public key, and the server stores it. Turning it off removes both.
// After either, the page reloads, so the push settings show or hide.
import { actions } from 'astro:actions';

const box = document.querySelector<HTMLElement>('[data-push]');

if (box) {
  const on = box.querySelector<HTMLButtonElement>('[data-push-on]')!;
  const offButton = box.querySelector<HTMLButtonElement>('[data-push-off]')!;
  const key = box.dataset.key ?? '';

  /** Shows one message, and which buttons fit. */
  const show = (message: string, buttons: { on?: boolean; off?: boolean } = {}) => {
    for (const element of box.querySelectorAll<HTMLElement>('[data-push-message]')) {
      element.hidden = element.dataset.pushMessage !== message;
    }
    on.hidden = !buttons.on;
    offButton.hidden = !buttons.off;
  };

  // Safari on iPhone and iPad gets pushes only for a site added to the Home Screen.
  const appleMobile =
    /iPhone|iPad|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const installed =
    matchMedia('(display-mode: standalone)').matches ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true;

  const subscription = async () =>
    (await navigator.serviceWorker.ready).pushManager.getSubscription();

  const refresh = async () => {
    if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
      show(appleMobile && !installed ? 'ios' : 'unsupported');
      return;
    }
    if (Notification.permission === 'denied') {
      show('blocked');
      return;
    }
    show('checking');
    const current = await subscription();
    show(current ? 'on' : '', { on: !current, off: !!current });
  };

  on.addEventListener('click', async () => {
    on.disabled = true;
    try {
      if ((await Notification.requestPermission()) !== 'granted') {
        show('blocked');
        return;
      }
      const registration = await navigator.serviceWorker.ready;
      const made = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: key,
      });
      const { endpoint, keys } = made.toJSON();
      const { error } = await actions.notifications.savePushDevice({
        endpoint: endpoint ?? '',
        p256dh: keys?.p256dh ?? '',
        auth: keys?.auth ?? '',
      });
      if (error) {
        await made.unsubscribe();
        throw error;
      }
      location.reload();
    } catch {
      show('failed', { on: true });
    } finally {
      on.disabled = false;
    }
  });

  offButton.addEventListener('click', async () => {
    offButton.disabled = true;
    try {
      const current = await subscription();
      if (current) {
        await actions.notifications.removePushDevice({ endpoint: current.endpoint });
        await current.unsubscribe();
      }
      location.reload();
    } catch {
      show('failed', { off: true });
    } finally {
      offButton.disabled = false;
    }
  });

  refresh().catch(() => show('unsupported'));
}

// Share in an activity's menu (ACT-02). Without JavaScript it's an email. With it, it's the
// phone's share sheet, or a copied link where there's no share sheet.
import { toast } from './toast';

const link = document.querySelector<HTMLAnchorElement>('[data-share]');

link?.addEventListener('click', async (event) => {
  const { title = '', url = location.href } = link.dataset;
  if (typeof navigator.share === 'function') {
    event.preventDefault();
    // Closing the share sheet without sharing rejects, which is fine.
    await navigator.share({ title, url }).catch(() => {});
  } else if (navigator.clipboard) {
    event.preventDefault();
    try {
      await navigator.clipboard.writeText(url);
      toast('Link copied.');
    } catch {
      location.href = link.href;
    }
  }
  link.closest('details')?.removeAttribute('open');
});

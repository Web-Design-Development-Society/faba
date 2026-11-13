// Shrinking a picture on the device before it uploads (MEDIA-01, src/components/PictureUpload.astro).
// A phone's photo is usually 3 to 5 MB, over the 2 MB limit, and an iPhone's starts out as HEIC.
// A picture bigger than 1600 px on its longest side, over 2 MB, or not a JPEG, PNG or WebP is
// redrawn as a JPEG at most 1600 px on its longest side. Redrawing also leaves out what the photo
// carried about itself, such as where it was taken. A small picture uploads as it is.
//
// Every picture also gets a small copy, at most 320 px, which cards show so Discover doesn't
// download whole photos (UI-03).
//
// Without JavaScript, or when the browser can't read the file, it uploads as it is, and the server
// says what's wrong, next to the form.
import { fitWithin, MAX_BYTES, MAX_SIDE, THUMB_MAX_BYTES, THUMB_SIDE } from '../lib/media';

const KEPT = ['image/jpeg', 'image/png', 'image/webp'];

/** The picture drawn at most `side` px on its longest side, as a JPEG of at most `max` bytes. */
async function redraw(
  bitmap: ImageBitmap,
  side: number,
  max: number,
  name: string
): Promise<File | null> {
  const { width, height } = fitWithin(bitmap.width, bitmap.height, side);
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d')!;
  // A JPEG has no transparency, so a see-through PNG goes on white, not black.
  context.fillStyle = 'white';
  context.fillRect(0, 0, width, height);
  context.drawImage(bitmap, 0, 0, width, height);

  // Lower the quality until it fits, which it almost always does at the first.
  let blob: Blob | null = null;
  for (const quality of [0.85, 0.75, 0.6, 0.45]) {
    blob = await new Promise<Blob | null>((resolve) =>
      canvas.toBlob(resolve, 'image/jpeg', quality)
    );
    if (blob && blob.size <= max) break;
  }
  return blob && blob.size <= max ? new File([blob], name, { type: 'image/jpeg' }) : null;
}

/** The picture redrawn smaller, or null when it's fine as it is, and its small copy for cards. */
async function prepare(file: File): Promise<{ picture: File | null; thumb: File | null }> {
  const bitmap = await createImageBitmap(file);
  try {
    const name = file.name.replace(/\.[^.]*$/, '') || 'picture';
    const big = Math.max(bitmap.width, bitmap.height) > MAX_SIDE;
    const picture =
      big || file.size > MAX_BYTES || !KEPT.includes(file.type)
        ? await redraw(bitmap, MAX_SIDE, MAX_BYTES, `${name}.jpg`)
        : null;
    const thumb = await redraw(bitmap, THUMB_SIDE, THUMB_MAX_BYTES, `${name}-small.jpg`);
    return { picture, thumb };
  } finally {
    bitmap.close();
  }
}

/** Puts `file` in a file input, as if it had been chosen. */
function choose(input: HTMLInputElement, file: File) {
  const files = new DataTransfer();
  files.items.add(file);
  input.files = files.files;
}

for (const form of document.querySelectorAll<HTMLFormElement>('form[data-picture]')) {
  form.addEventListener('submit', async (event) => {
    const input = form.querySelector<HTMLInputElement>('input[name="picture"]');
    const file = input?.files?.[0];
    // Once ready, the form posts the usual way.
    if (!input || !file || form.dataset.shrunk === 'yes') return;
    event.preventDefault();

    const button = form.querySelector<HTMLButtonElement>('button');
    const label = button?.textContent ?? '';
    if (button) {
      button.disabled = true;
      button.textContent = 'Getting the picture ready…';
    }
    try {
      const { picture, thumb } = await prepare(file);
      if (picture) choose(input, picture);
      const small = form.querySelector<HTMLInputElement>('input[data-thumb]');
      if (thumb && small) choose(small, thumb);
    } catch {
      // The browser can't read it, so the server decides, and says why if it's refused.
    }
    if (button) {
      button.disabled = false;
      button.textContent = label;
    }
    form.dataset.shrunk = 'yes';
    form.requestSubmit(button ?? undefined);
  });
}

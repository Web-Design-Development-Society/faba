// Shrinking a picture on the device before it uploads (MEDIA-01, src/components/PictureUpload.astro),
// and New activity's picture (MEDIA-02, src/components/CoverField.astro).
// A phone's photo is usually 3 to 5 MB, over the 2 MB limit, and an iPhone's starts out as HEIC.
// A picture bigger than 1600 px on its longest side, over 2 MB, or not a JPEG, PNG or WebP is
// redrawn as a JPEG at most 1600 px on its longest side. Redrawing also leaves out what the photo
// carried about itself, such as where it was taken. A small picture uploads as it is.
//
// Every picture also gets a small copy, at most 640 px, which cards show so Discover doesn't
// download whole photos (UI-03). A cover or banner also gets a medium copy, which a phone shows on
// the activity's or group's page (UI-27): a cover's is the whole picture, at most 1080 px on its
// longest side, since the page shows it whole (MEDIA-03), and a banner's is the middle of the
// picture at the banner's 3:1, at most 1080 px wide.
//
// Without JavaScript, or when the browser can't read the file, it uploads as it is, and the server
// says what's wrong, next to the form.
import {
  fitWithin,
  MAX_BYTES,
  MAX_SIDE,
  MEDIUM_MAX_BYTES,
  mediumCrop,
  THUMB_MAX_BYTES,
  THUMB_SIDE,
  wholeCopy,
} from '../lib/media';

const KEPT = ['image/jpeg', 'image/png', 'image/webp'];

/** The picture, or `crop` of it, drawn at `size`, as a JPEG of at most `max` bytes. */
async function redraw(
  bitmap: ImageBitmap,
  { width, height }: { width: number; height: number },
  max: number,
  name: string,
  crop = { sx: 0, sy: 0, sw: bitmap.width, sh: bitmap.height }
): Promise<File | null> {
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d')!;
  // A JPEG has no transparency, so a see-through PNG goes on white, not black.
  context.fillStyle = 'white';
  context.fillRect(0, 0, width, height);
  context.drawImage(bitmap, crop.sx, crop.sy, crop.sw, crop.sh, 0, 0, width, height);

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

/**
 * The picture redrawn smaller, or null when it's fine as it is, and its small copy for cards, at
 * most `side` px. A profile photo's is smaller, since faces are small (UI-11). With `shape`, a
 * banner also gets its medium copy at that shape, and a cover, with 'whole', its medium copy of
 * the whole picture (UI-27, MEDIA-03).
 */
async function prepare(
  file: File,
  side = THUMB_SIDE,
  shape?: number | 'whole'
): Promise<{ picture: File | null; thumb: File | null; middle: File | null }> {
  const bitmap = await createImageBitmap(file);
  try {
    const name = file.name.replace(/\.[^.]*$/, '') || 'picture';
    const { width, height } = bitmap;
    const big = Math.max(width, height) > MAX_SIDE;
    const picture =
      big || file.size > MAX_BYTES || !KEPT.includes(file.type)
        ? await redraw(bitmap, fitWithin(width, height), MAX_BYTES, `${name}.jpg`)
        : null;
    const thumb = await redraw(
      bitmap,
      fitWithin(width, height, side),
      THUMB_MAX_BYTES,
      `${name}-small.jpg`
    );
    const medium =
      shape === 'whole'
        ? wholeCopy(width, height)
        : shape
          ? mediumCrop(width, height, shape)
          : null;
    const middle = medium
      ? await redraw(bitmap, medium.size, MEDIUM_MAX_BYTES, `${name}-medium.jpg`, medium.crop)
      : null;
    return { picture, thumb, middle };
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

    // The button that posted it, such as New activity's Post activity (MEDIA-02).
    const button =
      (event.submitter as HTMLButtonElement | null) ??
      form.querySelector<HTMLButtonElement>('button');
    const label = button?.textContent ?? '';
    if (button) {
      button.disabled = true;
      button.textContent = 'Getting the picture ready…';
    }
    try {
      // A banner's medium copy is cut to its data-shape, and a cover's, with none, is whole.
      const medium = form.querySelector<HTMLInputElement>('input[data-medium]');
      const { picture, thumb, middle } = await prepare(
        file,
        Number(form.dataset.thumbSide) || undefined,
        medium ? Number(medium.dataset.shape) || 'whole' : undefined
      );
      if (picture) choose(input, picture);
      const small = form.querySelector<HTMLInputElement>('input[data-thumb]');
      if (thumb && small) choose(small, thumb);
      if (middle && medium) choose(medium, middle);
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

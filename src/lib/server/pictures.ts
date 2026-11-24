// Storing a picture in the bucket (MEDIA-01), for /api/media/upload and for New activity's picture
// (MEDIA-02). The Worker checks the file's own bytes and stores it under a random key, with the
// small and medium copies the device made beside it, if they're pictures no bigger than they should
// be. Postgres then points the activity, group or profile at it, and if that fails, drop() deletes
// the files again, so the bucket never keeps a picture nothing points to.
import { env } from 'cloudflare:workers';
import {
  MEDIUM_MAX_BYTES,
  mediumKey,
  pictureProblem,
  sniffPicture,
  THUMB_MAX_BYTES,
  thumbKey,
  type PictureType,
  wholeKey,
} from '../media';

const bucket = () => (env as unknown as { MEDIA: MediaBucket }).MEDIA;

/** Why a picture was refused, as a flash message's name. */
export type Refusal = 'upload_missing' | 'upload_too_big' | 'upload_type';

/** A stored picture: its key in the bucket, its type and its size. */
export interface Stored {
  key: string;
  type: PictureType;
  bytes: number;
}

/** Why `file` can't be stored, or null when it can. Reads its first bytes. */
export async function refusal(file: File): Promise<Refusal | null> {
  const problem = pictureProblem(file.size, new Uint8Array(await file.slice(0, 16).arrayBuffer()));
  if (!problem) return null;
  if (problem.startsWith('Choose')) return 'upload_missing';
  if (problem.includes('2 MB')) return 'upload_too_big';
  return 'upload_type';
}

/**
 * Stores `file` under a random key in `folder`, with the device's small copy and, for a cover or
 * banner, its medium copy, each left out if it isn't a picture or is too big. A cover's medium copy
 * is the whole picture, kept under a name of its own (MEDIA-03). Check refusal() first.
 */
export async function store(
  folder: 'activities' | 'groups' | 'profiles',
  file: File,
  copies: { thumb?: unknown; medium?: unknown }
): Promise<Stored> {
  const bytes = new Uint8Array(await file.arrayBuffer());
  const type = sniffPicture(bytes);
  if (!type) throw new Error('Not a picture. Check refusal() first.');
  const key = `${folder}/${crypto.randomUUID()}`;
  await bucket().put(key, bytes.buffer, { httpMetadata: { contentType: type } });

  /** Keeps the device's copy `sent` at `copy`, if it's a picture no bigger than `max`. */
  const keep = async (sent: unknown, max: number, copy: string) => {
    if (!(sent instanceof File) || sent.size === 0 || sent.size > max) return;
    const made = new Uint8Array(await sent.arrayBuffer());
    const madeType = sniffPicture(made);
    if (madeType)
      await bucket().put(copy, made.buffer, { httpMetadata: { contentType: madeType } });
  };
  await keep(copies.thumb, THUMB_MAX_BYTES, thumbKey(key));
  if (folder !== 'profiles') {
    const at = folder === 'activities' ? wholeKey(key) : mediumKey(key);
    await keep(copies.medium, MEDIUM_MAX_BYTES, at);
  }
  return { key, type, bytes: file.size };
}

/** Deletes the picture at `key` and its copies, including a cover's cut copy from before MEDIA-03. */
export async function drop(key: string) {
  await bucket().delete([key, thumbKey(key), mediumKey(key), wholeKey(key)]);
}

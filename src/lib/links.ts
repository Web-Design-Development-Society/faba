// Links made from what members type (ACT-02, design document section 7.6). Descriptions are plain
// text, so pages render these pieces as text and links, never as HTML.

/** A piece of plain text, which is a link when it has `href`. */
export interface Piece {
  text: string;
  href?: string;
}

const ADDRESS = /\b(?:https?:\/\/|www\.)[^\s<>"]+/gi;
const OPENING: Record<string, string> = { ')': '(', ']': '[' };

const count = (text: string, character: string) => text.split(character).length - 1;

/** Whether the address's last character more likely ends the sentence around it. */
function endsSentence(address: string) {
  const last = address.at(-1)!;
  if (".,;:!?'".includes(last)) return true;
  // A closing bracket belongs to the address only when it opens one too, as Wikipedia's do.
  const opening = OPENING[last];
  return !!opening && count(address, opening) < count(address, last);
}

/** `text` split into plain text and links to the web addresses in it. */
export function linkify(text: string): Piece[] {
  const pieces: Piece[] = [];
  let from = 0;
  for (const match of text.matchAll(ADDRESS)) {
    let address = match[0];
    while (address && endsSentence(address)) address = address.slice(0, -1);
    const href = /^www\./i.test(address) ? `https://${address}` : address;
    if (!URL.canParse(href)) continue;
    if (match.index > from) pieces.push({ text: text.slice(from, match.index) });
    pieces.push({ text: address, href });
    from = match.index + address.length;
  }
  if (from < text.length) pieces.push({ text: text.slice(from) });
  return pieces;
}

/**
 * A link that opens `place` in the phone's maps app: Apple Maps on Apple devices, and Google Maps
 * elsewhere. Every place is in or near Rexburg (ADR-017), so the search says so.
 */
export function mapsUrl(place: string, userAgent: string): string {
  const query = encodeURIComponent(/rexburg/i.test(place) ? place : `${place}, Rexburg, ID`);
  return /iPhone|iPad|Macintosh/.test(userAgent)
    ? `https://maps.apple.com/?q=${query}`
    : `https://www.google.com/maps/search/?api=1&query=${query}`;
}

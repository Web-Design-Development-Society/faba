// The create form's draft in local storage (ACT-03, design document section 7.7). It's kept
// until the activity is posted or the member starts over. Storage can be full or blocked, and then
// there's simply no draft.

const KEY = 'faba-new-activity';
// Details for attendees (ACT-09) stay out of it. They're often a home address, and on a shared
// computer, the next person to open New activity would see the draft.
const PRIVATE = new Set(['private_details']);

export function loadDraft(): Record<string, string> | null {
  try {
    const saved = localStorage.getItem(KEY);
    return saved ? JSON.parse(saved) : null;
  } catch {
    return null;
  }
}

export function saveDraft(form: HTMLFormElement) {
  const fields = Object.fromEntries(
    [...new FormData(form)].filter(
      (entry): entry is [string, string] => typeof entry[1] === 'string' && !PRIVATE.has(entry[0])
    )
  );
  try {
    localStorage.setItem(KEY, JSON.stringify(fields));
  } catch {
    // No draft this time.
  }
}

export function clearDraft() {
  try {
    localStorage.removeItem(KEY);
  } catch {
    // Nothing to clear.
  }
}

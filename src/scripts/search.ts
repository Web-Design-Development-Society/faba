// Search (SRCH-01). Recent searches stay in this browser only: a search saves its query, and the
// page without one lists the last few. Include past applies at once. Without JavaScript, or with
// storage turned off, the form still works.
const KEY = 'faba-recent-searches';
const KEEP = 5;

function recentSearches(): string[] {
  try {
    const saved: unknown = JSON.parse(localStorage.getItem(KEY) ?? '[]');
    return Array.isArray(saved) ? saved.filter((item) => typeof item === 'string') : [];
  } catch {
    return [];
  }
}

const q = new URLSearchParams(location.search).get('q')?.trim();
if (q) {
  const others = recentSearches().filter((item) => item.toLowerCase() !== q.toLowerCase());
  try {
    localStorage.setItem(KEY, JSON.stringify([q, ...others].slice(0, KEEP)));
  } catch {
    // Storage is off or full, so nothing is remembered.
  }
}

const recent = document.querySelector<HTMLElement>('[data-recent]');
const searches = recentSearches();
if (recent && searches.length) {
  recent.querySelector('ul')?.append(
    ...searches.map((search) => {
      const link = document.createElement('a');
      link.href = `/search?${new URLSearchParams({ q: search })}`;
      link.textContent = search;
      const item = document.createElement('li');
      item.append(link);
      return item;
    })
  );
  recent.hidden = false;
}

const form = document.querySelector<HTMLFormElement>('[data-search]');
form?.querySelector('[name="past"]')?.addEventListener('change', () => {
  if (form.querySelector<HTMLInputElement>('[name="q"]')?.value.trim()) form.requestSubmit();
});

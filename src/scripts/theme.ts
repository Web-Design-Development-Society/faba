// Me's Theme card (UI-34): a choice shows at once and saves, so Save is only for when JavaScript is
// off. The page comes back from the server in the chosen theme.
for (const form of document.querySelectorAll<HTMLFormElement>('[data-theme-form]')) {
  const save = form.querySelector<HTMLButtonElement>('[data-theme-save]');
  if (save) save.hidden = true;
  form.addEventListener('change', (event) => {
    const { value } = event.target as HTMLInputElement;
    const root = document.documentElement;
    if (value === 'light' || value === 'dark') root.dataset.theme = value;
    else delete root.dataset.theme;
    form.requestSubmit();
  });
}

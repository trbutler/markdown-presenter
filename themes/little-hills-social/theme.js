import {mount as mountBanner} from '../little-hills/theme.js';

export async function mount(root, options) {
  const {baseUrl, cue} = options;
  const banner = await mountBanner(root, {...options,
    baseUrl: new URL('../little-hills/', new URL(baseUrl, location.href)).href,
    cue: {...cue, variant: 'full-width', line2: ''},
  });
  const row = root.querySelector('.lh-socials');
  const icons = [];
  for (const [field, label] of [['facebook', 'Facebook'], ['x', 'X'], ['mastodon', 'Mastodon']]) {
    if (!cue[field]) continue;
    const account = document.createElement('span');
    account.className = 'lh-social-account';
    const icon = document.createElement('img');
    icon.src = `${baseUrl}assets/${field}.svg`;
    icon.alt = label;
    const handle = document.createElement('span');
    handle.textContent = cue[field];
    account.append(icon, handle); row.append(account); icons.push(icon);
  }
  await Promise.all(icons.map(icon => icon.decode()));
  // Keep each full handle intact, including the Mastodon server name.
  let size = parseFloat(getComputedStyle(row).fontSize);
  while (row.scrollWidth > row.clientWidth && size > 28) row.style.fontSize = `${--size}px`;
  return banner;
}

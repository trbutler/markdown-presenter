const clamp = x => Math.max(0, Math.min(1, x));
const ease = x => 1 - Math.pow(1 - clamp(x), 3);
const segment = (x, start, end) => ease((x - start) / (end - start));

export async function mount(root, {baseUrl, template, cue}) {
  root.innerHTML = template; // Trusted, installed theme markup. Cue content uses textContent.
  const stage = root.querySelector('.lh-stage');
  stage.classList.toggle('full-width', cue.variant === 'full-width');
  stage.classList.toggle('serene-sands', cue.font === 'serene-sands');
  const logo = stage.querySelector('.lh-logo');
  logo.src = `${baseUrl}assets/logo.svg`;
  const lines = [...stage.querySelectorAll('.lh-line')];
  lines[0].textContent = cue.line1 || '';
  lines[1].textContent = cue.line2 || '';
  await Promise.all([
    document.fonts.load(`400 48px "${cue.font === 'serene-sands' ? 'LH Serene Sands' : 'LH Quicksand'}"`),
    logo.decode(),
  ]);
  // Fit a single line without wrapping phone numbers or email addresses.
  for (const line of lines) {
    let size = parseFloat(getComputedStyle(line).fontSize);
    while (line.scrollWidth > line.clientWidth && size > 28) line.style.fontSize = `${--size}px`;
  }
  return {
    render({phase, progress, exitFrom = 1, width, height}) {
      const scale = Math.min(width / 1920, height / 1080);
      stage.style.transform = `translate(${(width - 1920 * scale) / 2}px,${(height - 1080 * scale) / 2}px) scale(${scale})`;
      // The regular exit seeks backward through the exact build-in poses.
      const reverse = cue.variant === 'regular';
      const entry = phase === 'entering' ? progress
        : phase === 'exiting' ? exitFrom * (reverse ? 1 - progress : 1) : 1;
      const out = phase === 'exiting' && !reverse ? progress : 0;
      const bands = [
        [stage.querySelector('.lh-main'), 0, .86, -1920, 0],
        [stage.querySelector('.lh-top'), .12, .95, 1920, .08],
        [stage.querySelector('.lh-bottom'), .06, 1, -1920, .06],
      ];
      for (const [band, start, end, offset, delay] of bands) {
        const entered = segment(entry, start, end);
        const exited = segment(out, delay, 1);
        const entryOffset = cue.variant === 'regular' ? -1920 : offset;
        const visible = entered * (1 - exited);
        band.style.transform = `translateX(${entryOffset * (1 - entered) + offset * entered * exited}px)`;
        band.style.opacity = String(visible);
      }
      const logoIn = segment(entry, 0, .85);
      const logoOut = segment(out, .05, 1);
      logo.style.transform = `translateX(${-240 * (1 - logoIn) + 60 * logoOut}px) rotateY(${90 * (1 - logoIn) + 90 * logoOut}deg)`;
      logo.style.opacity = String(logoIn * (1 - logoOut));
      stage.querySelector('.lh-copy').style.opacity = String(segment(entry, .30, 1) * (1 - segment(out, 0, .65)));
    },
    unmount() { root.replaceChildren(); },
  };
}

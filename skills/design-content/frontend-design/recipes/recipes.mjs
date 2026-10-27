// VFT adaptation, not upstream code. MIT; see third-party/taste-skill/LICENSE from the skill root.
// Content is visible before mount; callers must run the returned cleanup on component unmount.
export function mountExampleStack(root) {
  const button = root.querySelector('[data-next]');
  const status = root.querySelector('[data-status]');
  const cards = [...root.querySelectorAll('[data-card]')];
  if (!button || !status || cards.length < 2) throw new Error('Example stack needs a button, status and at least two cards');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const saved = cards.map((card) => ({ style: card.getAttribute('style'), hidden: card.getAttribute('aria-hidden') }));
  const originalDisabled = button.getAttribute('aria-disabled');
  const originalStatus = status.textContent;
  const restoreButton = () => {
    if (originalDisabled === null) button.removeAttribute('aria-disabled');
    else button.setAttribute('aria-disabled', originalDisabled);
  };
  let index = 0, busy = false, disposed = false, animations = [];
  const depthOf = (i) => (i - index + cards.length) % cards.length;
  const pose = (depth) => ({
    transform: `translateY(${-Math.min(depth, 2) * 24}px) scale(${1 - Math.min(depth, 2) * 0.06})`,
    opacity: depth < 3 ? '1' : '0',
  });
  const settle = () => {
    cards.forEach((card, i) => {
      const depth = depthOf(i);
      Object.assign(card.style, pose(depth), { zIndex: String(cards.length - depth) });
      card.setAttribute('aria-hidden', depth === 0 ? 'false' : 'true');
    });
    status.textContent = `${index + 1} / ${cards.length} — ${cards[index].querySelector('h3')?.textContent || 'Example'}`;
  };
  const cancel = () => {
    for (const animation of animations) animation.cancel();
    animations = [];
    if (!disposed) settle();
  };
  const advance = async () => {
    if (busy || disposed) return; // Repeated clicks are ignored until the current transition settles.
    busy = true;
    button.setAttribute('aria-disabled', 'true');
    const previous = cards.map((card) => ({ transform: card.style.transform, opacity: card.style.opacity }));
    const outgoing = index;
    index = (index + 1) % cards.length;
    settle();
    try {
      if (!reduced.matches && typeof cards[0].animate === 'function') {
        cards[outgoing].style.zIndex = String(cards.length + 1);
        animations = cards.map((card, i) => card.animate([
          previous[i],
          i === outgoing ? { transform: 'translateY(32px) scale(1.03)', opacity: '0' } : pose(depthOf(i)),
        ], { duration: i === outgoing ? 450 : 550, easing: 'cubic-bezier(0.22,1,0.36,1)' }));
        const results = await Promise.allSettled(animations.map((animation) => animation.finished));
        const failed = results.find((result) => result.status === 'rejected' && result.reason?.name !== 'AbortError');
        if (failed) throw failed.reason;
      }
    } finally {
      cancel();
      busy = false;
      if (!disposed) restoreButton();
    }
  };
  const click = () => { void advance().catch((error) => { console.error('Example stack failed', error); if (!disposed) status.textContent = 'Example changed without animation'; }); };
  const preferenceChanged = () => { if (reduced.matches) cancel(); };
  const visibilityChanged = () => { if (document.hidden) cancel(); };
  root.classList.add('is-enhanced');
  settle();
  button.addEventListener('click', click);
  reduced.addEventListener('change', preferenceChanged);
  document.addEventListener('visibilitychange', visibilityChanged);
  return () => {
    disposed = true;
    cancel();
    button.removeEventListener('click', click);
    reduced.removeEventListener('change', preferenceChanged);
    document.removeEventListener('visibilitychange', visibilityChanged);
    restoreButton();
    status.textContent = originalStatus;
    root.classList.remove('is-enhanced');
    cards.forEach((card, i) => {
      for (const [name, value] of [['style', saved[i].style], ['aria-hidden', saved[i].hidden]]) {
        if (value === null) card.removeAttribute(name); else card.setAttribute(name, value);
      }
    });
  };
}

// Requires the project's already-loaded GSAP + ScrollTrigger and the preserved stage.js/stage.css.
// No CDN injection, Lenis, global Stage.init() or automatic package installation.
export function mountOpeningScene(root) {
  if (!root?.querySelector('.scene-picture')) throw new Error('Opening scene needs .scene-picture');
  const stage = globalThis.Stage;
  if (!stage?.live) { root.classList.add('is-rest'); return () => root.classList.remove('is-rest'); }
  const mounted = stage.scene(root, {
    hold: 1,
    scrub: true,
    phone: 'rest',
    build(timeline, { q }) {
      timeline.fromTo(q('.scene-picture'),
        { clipPath: 'inset(20% 28%)', scale: 1.08 },
        { clipPath: 'inset(0%)', scale: 1, duration: 0.75 }, 0);
    },
  });
  return () => {
    mounted?.revert();
    const i = stage.scenes.indexOf(mounted);
    if (i !== -1) stage.scenes.splice(i, 1);
    root.classList.remove('is-live', 'is-rest');
    root.style.removeProperty('--hold');
    root.style.removeProperty('--p');
    delete root.dataset.beat;
  };
}

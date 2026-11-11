// Read-only light-DOM snapshot; candidates require review, not a WCAG compliance verdict.
// Keep self-contained so browser runners can serialize this function into page.evaluate().
export function collectMobileAudit() {
  const width = document.documentElement.clientWidth;
  const height = document.documentElement.clientHeight;
  const scrollWidth = document.scrollingElement?.scrollWidth ?? document.documentElement.scrollWidth;
  const viewport = document.querySelector('meta[name="viewport" i]')?.content ?? '';
  const limits = [...viewport.matchAll(/(?:^|[,;\s])\s*(user-scalable|maximum-scale)\s*=\s*([^,;\s]+)/gi)];
  const zoomRestricted = limits.some(([, key, value]) => key.toLowerCase() === 'user-scalable'
    ? /^(?:no|0)$/i.test(value)
    : Number.isFinite(Number(value)) && Number(value) < 2);
  const smallTargets = [];
  const smallInputs = [];
  let targetCount = 0;
  let inputCount = 0;
  const controls = document.querySelectorAll('a[href], button, input, select, textarea, summary, [role="button"], [role="link"], [role="checkbox"], [role="switch"], [role="tab"], [role="radio"], [tabindex]');
  for (const [index, element] of [...controls].entries()) {
    if (element.matches(':disabled') || element.closest('[hidden], [inert], [aria-hidden="true"]')) continue;
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    if (rect.width <= 0 || rect.height <= 0 || rect.bottom <= 0 || rect.top >= height || rect.right <= 0 || rect.left >= width) continue;
    if (style.display === 'none' || style.visibility !== 'visible' || Number(style.opacity) === 0) continue;
    const box = {
      index, tag: element.tagName.toLowerCase(),
      width: Math.round(rect.width * 100) / 100,
      height: Math.round(rect.height * 100) / 100,
    };
    if (rect.width < 44 || rect.height < 44) {
      targetCount++;
      if (smallTargets.length < 100) smallTargets.push({ ...box, below24: rect.width < 24 || rect.height < 24 });
    }
    const type = (element.getAttribute('type') ?? 'text').toLowerCase();
    const textInput = element.tagName === 'TEXTAREA' || (element.tagName === 'INPUT'
      && !['hidden', 'checkbox', 'radio', 'range', 'color', 'file', 'button', 'submit', 'reset', 'image'].includes(type));
    if (textInput && parseFloat(style.fontSize) < 16) {
      inputCount++;
      if (smallInputs.length < 100) smallInputs.push({ ...box, fontSize: parseFloat(style.fontSize) });
    }
  }
  const pageOverflow = scrollWidth > width + 1;
  return {
    status: pageOverflow || zoomRestricted || !viewport || targetCount || inputCount ? 'review' : 'clear',
    viewport: { width, height, scrollWidth, metaPresent: Boolean(viewport), zoomRestricted },
    pageOverflow,
    smallTargets: { count: targetCount, candidates: smallTargets },
    smallInputs: { count: inputCount, candidates: smallInputs },
    limitations: ['current viewport and light DOM only', 'no iframe or shadow DOM scan', 'no hit testing, spacing exceptions or occlusion check', 'no keyboard, touch, safe-area, device or business verification'],
  };
}

// 测量一个 MasterGo 画板的直接子级、嵌套文本和相邻间距。
//
// 用法：先填写 BOARD_ID，再把整个 `() => { ... }` 作为浏览器 evaluate 函数执行。
// NAMES 可限定精确节点名；Y_MIN/Y_MAX 可裁剪返回范围。
() => {
  const BOARD_ID = '';
  const NAMES = [];
  const Y_MIN = -Infinity;
  const Y_MAX = Infinity;

  const mg = window.mg;
  if (!BOARD_ID) return { error: '请先设置 BOARD_ID' };
  if (!mg || typeof mg.getNodeById !== 'function') return { error: 'window.mg.getNodeById 不可用' };
  const node = mg.getNodeById(BOARD_ID);
  if (!node?.absoluteBoundingBox) return { error: `board not found / no bbox: ${BOARD_ID}` };

  const base = node.absoluteBoundingBox;
  const rgb = (color) => color
    ? `rgb(${Math.round(color.r * 255)},${Math.round(color.g * 255)},${Math.round(color.b * 255)})`
    : null;
  const fillOf = (target) => {
    try {
      if (!Array.isArray(target.fills)) return null;
      const fill = target.fills.find((item) => item.visible !== false);
      if (!fill) return null;
      if (fill.type === 'SOLID') return rgb(fill.color);
      if (fill.type?.startsWith('GRADIENT')) {
        return `GRAD[${(fill.gradientStops || []).map((stop) => rgb(stop.color)).join(' ')}]`;
      }
      return fill.type === 'IMAGE' ? 'IMG' : fill.type;
    } catch {
      return null;
    }
  };
  const metricsOf = (target) => {
    const box = target.absoluteBoundingBox;
    if (!box) return null;
    const width = target.width ?? box.width;
    const height = target.height ?? box.height;
    return {
      x: Math.round(box.x - base.x),
      y: Math.round(box.y - base.y),
      w: Math.round(width),
      h: Math.round(height),
      right: Math.round(box.x - base.x + width),
      bottom: Math.round(box.y - base.y + height),
    };
  };
  const describe = (target) => {
    const metrics = metricsOf(target);
    if (!metrics || metrics.y < Y_MIN || metrics.y > Y_MAX) return null;
    const result = { name: target.name, type: target.type, ...metrics };
    const fill = fillOf(target);
    if (fill) result.fill = fill;
    if (target.cornerRadius != null) result.r = Math.round(target.cornerRadius);
    if (typeof target.characters === 'string' && target.characters.trim()) {
      result.text = target.characters.trim().replace(/\s+/g, ' ').slice(0, 60);
      if (typeof target.fontSize === 'number') result.font = Math.round(target.fontSize);
    }
    return result;
  };

  const blocks = [];
  const texts = [];
  if (NAMES.length) {
    const wanted = new Set(NAMES);
    const seen = new Set();
    const walk = (target) => {
      if (wanted.has(target.name) && !seen.has(target.id)) {
        seen.add(target.id);
        const result = describe(target);
        if (result) blocks.push(result);
      }
      (target.children || []).forEach(walk);
    };
    walk(node);
  } else {
    (node.children || []).forEach((child) => {
      const result = describe(child);
      if (result) blocks.push(result);
    });
    const walkText = (target) => {
      if (typeof target.characters === 'string' && target.characters.trim()) {
        const result = describe(target);
        if (result) texts.push(result);
      }
      (target.children || []).forEach(walkText);
    };
    walkText(node);
  }

  blocks.sort((left, right) => left.y - right.y);
  const gaps = [];
  if (!NAMES.length) {
    blocks.forEach((block, index) => {
      const previous = blocks.slice(0, index)
        .filter((candidate) => candidate.bottom <= block.y
          && Math.min(candidate.right, block.right) > Math.max(candidate.x, block.x))
        .sort((left, right) => right.bottom - left.bottom)[0];
      if (previous) gaps.push({ from: previous.name, to: block.name, gap: block.y - previous.bottom });
    });
  }
  const boardWidth = node.width ?? base.width;
  const boardHeight = node.height ?? base.height;
  const nonNegativeX = blocks.map((block) => block.x).filter((x) => x >= 0);
  return {
    board: node.name,
    w: Math.round(boardWidth),
    h: Math.round(boardHeight),
    leftPadding: nonNegativeX.length ? Math.min(...nonNegativeX) : null,
    blocks,
    texts,
    gaps,
  };
}

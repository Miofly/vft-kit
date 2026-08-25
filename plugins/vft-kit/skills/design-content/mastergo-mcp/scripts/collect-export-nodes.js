// 列出被标记为切图（有导出设置）的节点。
//
// 用法：把整个 `(options) => { ... }` 作为浏览器 evaluate 函数执行。手动执行时可不传参，
// 直接改下面的 ROOT_ID；脚本调用时传 `{ rootId: '3:01618' }` 限定范围。
// 前提：页面已加载 MasterGo，且 window.mg.document 可用。
//
// 两类节点都算切图：显式标了导出设置的节点，以及切片工具画出来的 SLICE 节点
// （SLICE 的 exportSettings 可能是空数组，按 PNG 1x 兜底）。
(options = {}) => {
  const ROOT_ID = options.rootId || ''; // 留空表示当前页整页
  const mg = window.mg;
  if (!mg || !mg.document) {
    return { error: 'window.mg.document 不可用——确认页面是已加载的 MasterGo 文件' };
  }

  const findById = (node, id) => {
    if (node.id === id) return node;
    for (const child of node.children || []) {
      const hit = findById(child, id);
      if (hit) return hit;
    }
    return null;
  };

  const root = ROOT_ID ? findById(mg.document, ROOT_ID) : mg.document.currentPage;
  if (!root) return { error: `找不到节点 ${ROOT_ID}` };

  const settingsOf = (node) => {
    let raw = [];
    try {
      raw = JSON.parse(JSON.stringify(node.exportSettings || []));
    } catch {}
    if (!raw.length && node.type === 'SLICE') raw = [{ format: 'PNG', constraint: { type: 'SCALE', value: 1 } }];
    return raw.map((setting) => ({
      format: setting.format || 'PNG', // 没写格式一律按 PNG
      constraintType: setting.constraint?.type || 'SCALE',
      constraintValue: setting.constraint?.value ?? 1,
      suffix: setting.fileName || '',
    }));
  };

  const exports = [];
  let total = 0;
  // boardWidth 取「离画板最近的那层」宽度：倍率要按设计稿画板宽算，不能按图标自己的宽算。
  (function walk(node, board) {
    total++;
    const currentBoard = board || (node.type === 'FRAME' || node.type === 'COMPONENT' ? node : null);
    const settings = settingsOf(node);
    if (settings.length) {
      exports.push({
        id: node.id,
        name: node.name,
        type: node.type,
        w: Math.round(node.width),
        h: Math.round(node.height),
        boardId: currentBoard?.id || null,
        boardName: currentBoard?.name || null,
        boardWidth: currentBoard ? Math.round(currentBoard.width) : null,
        boardHeight: currentBoard ? Math.round(currentBoard.height) : null,
        settings,
      });
    }
    (node.children || []).forEach((child) => walk(child, currentBoard));
  })(root, root.type === 'FRAME' || root.type === 'COMPONENT' ? root : null);

  return {
    rootId: root.id,
    rootName: root.name,
    rootType: root.type,
    rootWidth: root.width ? Math.round(root.width) : null,
    rootHeight: root.height ? Math.round(root.height) : null,
    scanned: total,
    count: exports.length,
    exports,
  };
}

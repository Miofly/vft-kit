// 枚举 MasterGo 文件的页面和顶层画板。
//
// 用法：把整个 `() => { ... }` 作为浏览器 evaluate 函数执行。
// 前提：页面已加载 MasterGo，且 window.mg.document 可用。
// 原型预览页可能多包一层容器；先看 nestedCandidate，确认后再打开显式钻层开关。
() => {
  const DRILL_SINGLE_WRAPPER = false;
  const mg = window.mg;
  if (!mg || !mg.document) {
    return { error: 'window.mg.document 不可用——确认页面是已加载的 MasterGo 文件' };
  }

  const sizeOf = (node) => {
    try {
      if (node.width != null && node.height != null) {
        return { w: Math.round(node.width), h: Math.round(node.height) };
      }
      const box = node.absoluteBoundingBox;
      if (box) return { w: Math.round(box.width), h: Math.round(box.height) };
    } catch {}
    return {};
  };
  const isPrototype = /\/prototyping(?:\/|$)/.test(window.location?.pathname || '');

  const pages = (mg.document.children || []).map((page) => {
    const topLevel = page.children || [];
    const candidate = isPrototype && topLevel.length === 1 && (topLevel[0].children || []).length > 1
      ? topLevel[0]
      : null;
    const wrapper = DRILL_SINGLE_WRAPPER ? candidate : null;
    const units = (wrapper ? wrapper.children : topLevel).filter((node) => node.type !== 'CONNECTOR');
    return {
      pageId: page.id,
      pageName: page.name,
      dug: Boolean(wrapper),
      container: wrapper?.name,
      nestedCandidate: candidate ? {
        id: candidate.id,
        name: candidate.name,
        children: candidate.children.filter((node) => node.type !== 'CONNECTOR').map((node) => ({
          id: node.id,
          name: node.name,
          type: node.type,
          ...sizeOf(node),
        })),
      } : undefined,
      children: units.map((node) => ({
        id: node.id,
        name: node.name,
        type: node.type,
        ...sizeOf(node),
      })),
    };
  });

  return {
    documentId: mg.documentId,
    currentPageId: mg.document.currentPage?.id,
    pages,
  };
}

// 按画板递归提取 MasterGo 文案和便签批注。
//
// 用法：把整个 `() => { ... }` 作为浏览器 evaluate 函数执行。
// PAGE_ID 为 null 时抽取全部页面；需要控制返回体积时填写页面 ID 或调小 MAX_LEN。
() => {
  const PAGE_ID = null;
  const MAX_LEN = 4000;
  const DRILL_SINGLE_WRAPPER = false;
  const mg = window.mg;
  if (!mg || !mg.document) return { error: 'window.mg.document 不可用' };

  const collect = (node, texts) => {
    const value = node?.characters;
    if (typeof value === 'string' && value.trim()) texts.push(value.trim().slice(0, MAX_LEN));
    (node?.children || []).forEach((child) => collect(child, texts));
  };
  const isPrototype = /\/prototyping(?:\/|$)/.test(window.location?.pathname || '');

  const extractPage = (page) => {
    const topLevel = page.children || [];
    const candidate = isPrototype && topLevel.length === 1 && (topLevel[0].children || []).length > 1
      ? topLevel[0]
      : null;
    const wrapper = DRILL_SINGLE_WRAPPER ? candidate : null;
    const units = (wrapper ? wrapper.children : topLevel).filter((node) => node.type !== 'CONNECTOR');
    const boards = units.map((node) => {
      const texts = [];
      collect(node, texts);
      return { id: node.id, name: node.name, type: node.type, texts };
    }).filter((board) => board.texts.length > 0);
    return { pageId: page.id, pageName: page.name, dug: Boolean(wrapper), boards };
  };

  let pages = mg.document.children || [];
  if (PAGE_ID) pages = pages.filter((page) => page.id === PAGE_ID);
  return { documentId: mg.documentId, pages: pages.map(extractPage) };
}

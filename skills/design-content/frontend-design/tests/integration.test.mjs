import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import test from 'node:test';

const skill = path.resolve(fileURLToPath(new URL('./', import.meta.url)), '..');
const at = (...parts) => path.join(skill, ...parts);
const text = (file) => readFileSync(file, 'utf8');
const sha256 = (file) => createHash('sha256').update(readFileSync(file)).digest('hex');
function files(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const file = path.join(directory, entry.name);
    return entry.isDirectory() ? files(file) : [file];
  });
}
const references = files(at('references')).filter((file) => file.endsWith('.md'));
const activeDocs = [at('SKILL.md'), at('THIRD_PARTY_NOTICES.md'), ...references];
const linksOf = (file) => [...text(file).matchAll(/\[[^\]]*\]\(([^)\s]+)\)/g)].map((match) => match[1])
  .filter((href) => !/^(?:https?:|mailto:|#)/.test(href));

test('every route and local link resolves, and every reference is reachable', () => {
  for (const file of activeDocs) {
    for (const href of linksOf(file)) {
      assert.ok(existsSync(path.resolve(path.dirname(file), href.split('#')[0])), `${path.relative(skill, file)}: ${href}`);
    }
  }
  // Backticked skill-root paths in docs must exist too (component, recipe, search, extract entry points).
  for (const file of activeDocs) {
    for (const [, rel] of text(file).matchAll(/`((?:components|recipes|search|extract|assets|licenses)\/[\w./-]+?\.(?:tsx|ts|mjs|js|css|json|md|mdx|py|html|woff2|txt))`/g)) {
      assert.ok(existsSync(at(rel)), `${path.relative(skill, file)}: ${rel}`);
    }
  }
  const linked = new Set([at('SKILL.md'), ...references].flatMap((file) => linksOf(file)
    .map((href) => path.resolve(path.dirname(file), href.split('#')[0]))));
  for (const file of references) assert.ok(linked.has(file), `orphan reference ${path.basename(file)}`);
  assert.ok(text(at('SKILL.md')).split('\n').length < 500);
});

test('functional layout only: no repository mirrors, provenance dumps, or personal paths', () => {
  const all = files(skill);
  assert.deepEqual(all.filter((file) => path.basename(file) === 'SKILL.md'), [at('SKILL.md')]);
  assert.deepEqual(all.filter((file) => /(?:\.pyc$|\/__pycache__\/|\.DS_Store$)/.test(file)), []);
  for (const gone of ['vendor', 'third-party', 'SOURCES.md']) assert.ok(!existsSync(at(gone)), gone);
  assert.deepEqual(all.filter((file) => /(?:UPSTREAM|SOURCE-MANIFEST|sources-[\w-]+\.md$|verify\.mjs$)/.test(file)), []);
  for (const file of activeDocs) {
    assert.doesNotMatch(text(file), /\/Users\/[a-zA-Z][\w-]*\/|[\w-]+\/\.secrets|vft-kit:replicate-web-style/, file);
  }
});

test('three case studies keep full-page, narrow-screen and entry lessons', () => {
  const cases = text(at('references/case-studies.md'));
  for (const example of ['educational-platform', 'pet-grooming', 'luxury-ecommerce']) {
    assert.ok(cases.includes(`https://www.uupm.cc/demo/${example}`), example);
  }
  for (const heading of ['## 教育平台', '## 宠物美容', '## 奢侈品电商', '### 迁移规范', '### Taste 展示页：叠卡切换']) {
    assert.ok(cases.includes(heading), heading);
  }
  assert.match(cases, /390px|窄屏|手机/);
});

test('style search runs locally over the bundled data', () => {
  const out = execFileSync('python3', ['-B', at('search/scripts/search.py'), 'claymorphism playful education', '--domain', 'style', '-n', '1', '--json'],
    { encoding: 'utf8', env: { ...process.env, PYTHONDONTWRITEBYTECODE: '1' } });
  assert.match(out, /claymorphism/i);
});

const aliasMaps = {
  'components/motion': [['@/hooks/', 'components/motion/hooks/'], ['@/lib/', 'components/motion/lib/']],
  'components/ui': [['@/registry/new-york-v4/', 'components/ui/'], ['@shadcn/react/', 'components/ui/packages/react/']],
  'components/effects': [['@/lib/', 'components/effects/lib/'], ['@/components/ui/', 'components/effects/ui/'], ['@/registry/magicui/', 'components/effects/magicui/']],
};
const sourceFiles = (base) => files(at(base)).filter((file) => /\.tsx?$/.test(file) && path.basename(file) !== '_registry.ts');

test('component source keeps a closed local import graph under documented aliases', () => {
  for (const [base, aliases] of Object.entries(aliasMaps)) {
    const sources = sourceFiles(base);
    assert.ok(sources.length > 30, base);
    for (const file of sources) {
      for (const [, spec] of text(file).matchAll(/(?:from|import)\s+['"]([^'"]+)['"]/g)) {
        let target;
        if (spec.startsWith('.')) target = path.resolve(path.dirname(file), spec);
        else {
          const alias = aliases.find(([prefix]) => spec.startsWith(prefix));
          if (!alias) { assert.ok(!spec.startsWith('@/'), `${path.relative(skill, file)}: unmapped ${spec}`); continue; }
          target = at(alias[1] + spec.slice(alias[0].length));
        }
        assert.ok(['', '.ts', '.tsx', '/index.ts', '/index.tsx'].some((ext) => existsSync(target + ext)), `${path.relative(skill, file)}: ${spec}`);
      }
    }
  }
  const motion = files(at('components/motion/core')).map((file) => path.basename(file, '.tsx'));
  assert.equal(motion.length, 33);
  for (const name of motion) assert.ok(existsSync(at('components/motion/docs', name, 'page.mdx')), `${name}: missing props/usage doc`);
});

test('effects index points at real components, docs and keyframes', () => {
  const index = JSON.parse(text(at('components/effects/index.json')));
  const names = index.components.map((item) => item.name);
  assert.equal(new Set(names).size, names.length);
  assert.deepEqual(names.slice().sort(), files(at('components/effects/magicui')).map((file) => path.basename(file, '.tsx')).sort());
  for (const item of index.components) {
    assert.ok(existsSync(at('components/effects', item.file)), item.name);
    if (item.docs) assert.ok(existsSync(at('components/effects', item.docs)), item.name);
  }
  const css = text(at('components/effects/globals.css'));
  for (const name of ['marquee', 'shimmer-slide', 'ripple', 'aurora']) {
    assert.match(css, new RegExp(`@keyframes ${name}\\b`), name);
  }
});

test('optional TypeScript syntax check of every bundled TS/TSX file', { skip: !process.env.TYPESCRIPT_PATH && 'set TYPESCRIPT_PATH to an installed typescript module' }, () => {
  const ts = createRequire(import.meta.url)(process.env.TYPESCRIPT_PATH);
  for (const base of Object.keys(aliasMaps)) {
    for (const file of files(at(base)).filter((item) => /\.tsx?$/.test(item))) {
      const result = ts.transpileModule(text(file), { fileName: file, reportDiagnostics: true, compilerOptions: { jsx: ts.JsxEmit.Preserve, target: ts.ScriptTarget.ES2022 } });
      assert.deepEqual(result.diagnostics.map((item) => ts.flattenDiagnosticMessageText(item.messageText, '\n')), [], path.relative(skill, file));
    }
  }
});

test('restricted libraries are documented boundaries, never bundled source', () => {
  const all = files(skill);
  assert.deepEqual(all.filter((file) => /react-bits|animate-ui|\.(?:glsl|frag|vert|vue)$/i.test(path.relative(skill, file))), []);
  for (const file of all.filter((item) => /\.(?:tsx?|jsx?|mjs|css|json)$/.test(item) && !item.startsWith(at('tests')))) {
    assert.doesNotMatch(text(file), /Commons Clause|@animate-ui\/|DavidHDev\/react-bits/, path.relative(skill, file));
  }
  const notices = text(at('THIRD_PARTY_NOTICES.md'));
  assert.match(notices, /React Bits[\s\S]*Animate UI[\s\S]*Commons Clause/);
});

test('consolidated notices preserve original license texts and attribution', () => {
  const notices = text(at('THIRD_PARTY_NOTICES.md'));
  for (const dir of ['search/', 'components/motion/', 'components/ui/', 'components/effects/', 'recipes/', 'examples/design-md/', 'extract/', 'assets/fonts/geist/']) {
    assert.ok(notices.includes(`\`${dir}`), dir);
  }
  const expected = [
    '0d542e0c8804e39aa7f37eb00da5a762149dc682d7829451287e11b938e94594',
    '6d4bdc9a9cf30e7beb593475fdcdbf29f981ea6bd7923f202866145409f87b44',
    '56e2dc0100744b958d87e5fc790f4e5ed2b5f483d6f2cbade4b6f7a0f5a03862',
    '28c03a23860adc110cef0c35ff4e45aaadabebe4d021cbe1f3b6bd14e6af662a',
    '02bb8c3b4e70190e3986c0404ad2fd8d639b4f534252d82379cc1b502b6d1812',
    'c60a093c2845fd9fb82f9c6f742ece31f379f8190b535309d32d66c45ccffdcb',
    '0147b84235ed916b8b4e89c1f80655351c5afe7d211b629be61f553a227b34ba',
    'f668f5ef3635eb906f10b1eea9a32e449eb6e1a183ab6879ef6d56c0980dd2f3',
    '1564074e13439397221ffd522e2e504d56561994a23d371aa5e3ad43e4f5423f',
    '4575a543ab88dad12ccea7d97e563d0bce5b448b06072e65d3264497dad326df',
    '738f69dfa83db5c347c678fb9d90e560877059f0de93a327c39001bff92dc014',
  ];
  const actual = [...notices.matchAll(/```text\n([\s\S]*?)```/g)]
    .map((match) => createHash('sha256').update(match[1]).digest('hex'));
  assert.deepEqual(actual, expected);
  assert.ok(!existsSync(at('licenses')));
  assert.ok(!existsSync(at('LICENSE.txt')));
});

test('bundled Geist fonts retain the recorded official bytes and OFL', () => {
  const directory = at('assets/fonts/geist');
  for (const [name, bytes, hash] of [
    ['Geist-Variable.woff2', 69760, '2ffebe993e969069a9789d15164b7715d42491b5835516c5e3b935d5f81b05f1'],
    ['GeistMono-Variable.woff2', 71596, 'afaacc4c5fbba89d2ebf7a02dc4070208540874592a5504d57175782fe893101'],
  ]) {
    const file = path.join(directory, name);
    assert.equal(readFileSync(file).subarray(0, 4).toString(), 'wOF2');
    assert.equal(readFileSync(file).length, bytes);
    assert.equal(sha256(file), hash);
  }
  assert.match(text(path.join(directory, 'OFL-1.1.txt')), /SIL OPEN FONT LICENSE Version 1\.1/);
});

test('motion recipes state/cleanup regression and extraction boundary checks pass', () => {
  for (const script of ['recipes/recipes.test.mjs', 'extract/tests/run-tests.mjs', 'extract/tests/local-boundaries.mjs']) {
    execFileSync(process.execPath, [at(script)], { encoding: 'utf8' });
  }
});

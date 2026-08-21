#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const skillsRoot = path.join(repoRoot, 'plugins/vft-kit/skills');
const catalog = JSON.parse(fs.readFileSync(path.join(repoRoot, 'catalog/skills.json'), 'utf8'));
const errors = [];
const categoryIds = new Set();
const catalogSkills = new Map();

for (const category of catalog.categories ?? []) {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(category.id ?? '')) {
    errors.push(`invalid category id: ${category.id}`);
  }
  if (categoryIds.has(category.id)) errors.push(`duplicate category: ${category.id}`);
  categoryIds.add(category.id);

  if (!category.name || !category.description || !category.skills?.length) {
    errors.push(`incomplete category: ${category.id}`);
    continue;
  }
  if (category.skills.join('\n') !== [...category.skills].sort().join('\n')) {
    errors.push(`skills not sorted: ${category.id}`);
  }

  for (const skill of category.skills) {
    if (catalogSkills.has(skill)) errors.push(`skill listed more than once: ${skill}`);
    catalogSkills.set(skill, category.id);
  }
}

const expectedSkillRoots = [...categoryIds].sort().map((category) => `./skills/${category}`);
for (const manifestPath of [
  'plugins/vft-kit/.claude-plugin/plugin.json',
  'plugins/vft-kit/.codex-plugin/plugin.json',
]) {
  const manifest = JSON.parse(fs.readFileSync(path.join(repoRoot, manifestPath), 'utf8'));
  const skillRoots = Array.isArray(manifest.skills) ? [...manifest.skills].sort() : [manifest.skills];
  if (skillRoots.join('\n') !== expectedSkillRoots.join('\n')) {
    errors.push(`manifest skill roots do not match catalog: ${manifestPath}`);
  }
}

const trackedEntries = execFileSync('git', ['ls-files'], { cwd: repoRoot, encoding: 'utf8' })
  .split('\n')
  .map((file) => {
    const match = file.match(/^plugins\/vft-kit\/skills\/([^/]+)\/([^/]+)\/SKILL\.md$/);
    return match ? { file, category: match[1], skill: match[2] } : null;
  })
  .filter(Boolean);
const trackedSkills = new Map();

for (const entry of trackedEntries) {
  if (trackedSkills.has(entry.skill)) errors.push(`tracked skill exists more than once: ${entry.skill}`);
  trackedSkills.set(entry.skill, entry.category);

  const catalogCategory = catalogSkills.get(entry.skill);
  if (!catalogCategory) errors.push(`tracked skill is not categorized: ${entry.skill}`);
  else if (catalogCategory !== entry.category) {
    errors.push(`skill is in wrong directory: ${entry.skill} (${entry.category}, expected ${catalogCategory})`);
  }

  const content = fs.readFileSync(path.join(repoRoot, entry.file), 'utf8');
  const frontmatterName = content.match(/^---\s*\n[\s\S]*?^name:\s*([^\n]+)$/m)?.[1]?.trim();
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(frontmatterName ?? '')) {
    errors.push(`invalid frontmatter name: ${entry.skill} (${frontmatterName ?? 'missing'})`);
  }
}

for (const skill of catalogSkills.keys()) {
  if (!trackedSkills.has(skill)) errors.push(`categorized skill is not tracked: ${skill}`);
}

const untrackedSkills = [];
for (const categoryEntry of fs.readdirSync(skillsRoot, { withFileTypes: true })) {
  if (!categoryEntry.isDirectory()) continue;
  if (!categoryIds.has(categoryEntry.name)) errors.push(`unknown category directory: ${categoryEntry.name}`);
  const categoryRoot = path.join(skillsRoot, categoryEntry.name);
  for (const skillEntry of fs.readdirSync(categoryRoot, { withFileTypes: true })) {
    if (
      skillEntry.isDirectory() &&
      !trackedSkills.has(skillEntry.name) &&
      fs.existsSync(path.join(categoryRoot, skillEntry.name, 'SKILL.md'))
    ) {
      untrackedSkills.push(`${categoryEntry.name}/${skillEntry.name}`);
    }
  }
}

if (errors.length) {
  console.error(errors.map((error) => `ERROR ${error}`).join('\n'));
  process.exit(1);
}

console.log(`skill catalog: ${trackedEntries.length} skills in ${categoryIds.size} categories`);
for (const skill of untrackedSkills) console.warn(`WARN untracked skill not categorized: ${skill}`);

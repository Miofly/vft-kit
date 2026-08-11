#!/usr/bin/env node

import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs'
import { basename, join, relative, resolve } from 'node:path'

const args = process.argv.slice(2)
const target = args[0]
const profileFlag = args.indexOf('--profile')
const profilePath = profileFlag === -1 ? null : args[profileFlag + 1]

function listDirectory(root, directory = root) {
  return readdirSync(directory).flatMap((name) => {
    const path = join(directory, name)
    return statSync(path).isDirectory() ? listDirectory(root, path) : [relative(root, path).replaceAll('\\', '/')]
  })
}

function openTarget(input) {
  const path = resolve(input)
  if (!existsSync(path)) throw new Error(`Target not found: ${path}`)

  if (statSync(path).isDirectory()) {
    const entries = listDirectory(path)
    return { kind: 'directory', path, entries, read: (entry) => readFileSync(join(path, entry), 'utf8') }
  }

  const entries = execFileSync('unzip', ['-Z1', path], { encoding: 'utf8' }).trim().split(/\r?\n/).filter(Boolean)
  return { kind: 'zip', path, entries, read: (entry) => execFileSync('unzip', ['-p', path, entry], { encoding: 'utf8' }) }
}

function localized(value, manifest, source) {
  const match = typeof value === 'string' && value.match(/^__MSG_(.+)__$/)
  if (!match) return value
  const locales = [manifest.default_locale, 'en'].filter(Boolean)
  for (const locale of [...new Set(locales)]) {
    const entry = `_locales/${locale}/messages.json`
    if (!source.entries.includes(entry)) continue
    const messages = JSON.parse(source.read(entry))
    if (messages[match[1]]?.message) return messages[match[1]].message
  }
  return null
}

function inspect(source) {
  const errors = []
  const warnings = []
  const nestedManifest = source.entries.find((entry) => entry.endsWith('/manifest.json'))

  if (!source.entries.includes('manifest.json')) {
    errors.push(nestedManifest ? `manifest.json is nested at ${nestedManifest}; ZIP contents must be at the archive root` : 'manifest.json is missing')
    return { ok: false, errors, warnings }
  }

  let manifest
  try { manifest = JSON.parse(source.read('manifest.json')) } catch (error) { errors.push(`Invalid manifest.json: ${error.message}`) }
  if (!manifest) return { ok: false, errors, warnings }

  if (manifest.manifest_version !== 3) errors.push(`Expected Manifest V3, found ${manifest.manifest_version ?? 'none'}`)
  for (const field of ['name', 'version', 'description']) if (!manifest[field]) errors.push(`Missing manifest field: ${field}`)

  const icon128 = manifest.icons?.['128']
  if (!icon128) warnings.push('No 128px store icon declared')
  else if (!source.entries.includes(icon128)) errors.push(`Declared 128px icon is missing: ${icon128}`)

  const permissions = [...new Set([...(manifest.permissions || []), ...(manifest.optional_permissions || [])])]
  const hosts = [...new Set([...(manifest.host_permissions || []), ...(manifest.optional_host_permissions || [])])]
  const sensitive = ['debugger', 'nativeMessaging', 'management', 'history', 'cookies', 'webRequestBlocking']
  for (const permission of permissions.filter((item) => sensitive.includes(item))) warnings.push(`Sensitive permission requires strong justification: ${permission}`)
  if (hosts.some((host) => host === '<all_urls>' || host === 'http://*/*' || host === 'https://*/*')) warnings.push('Broad host access may trigger deeper review')

  const name = localized(manifest.name, manifest, source)
  const description = localized(manifest.description, manifest, source)
  if (!name) errors.push('Unable to resolve localized extension name')
  if (!description) errors.push('Unable to resolve localized extension description')

  return {
    ok: errors.length === 0,
    target: source.path,
    packageType: source.kind,
    files: source.entries.length,
    manifest: {
      manifestVersion: manifest.manifest_version,
      name,
      version: manifest.version,
      description,
      defaultLocale: manifest.default_locale || null,
      permissions,
      hostPermissions: hosts,
      icon128: icon128 || null
    },
    errors,
    warnings
  }
}

function readProfile(input) {
  if (!input) return null
  const path = resolve(input)
  if (!existsSync(path)) throw new Error(`Profile not found: ${path}`)
  const profile = JSON.parse(readFileSync(path, 'utf8'))
  if (profile?.schemaVersion !== 1) throw new Error('Profile schemaVersion must be 1')
  if (!Array.isArray(profile.privacy?.userDataCategories)) throw new Error('privacy.userDataCategories must be an array')
  if (!Array.isArray(profile.privacy?.limitedUseConfirmations)) throw new Error('privacy.limitedUseConfirmations must be an array')
  for (const field of ['traderStatus', 'publicEmail', 'postalAddress']) {
    if (profile.legalProfile?.[field] !== 'preserve') throw new Error(`legalProfile.${field} must be "preserve"; legal identity values do not belong in this template`)
  }
  return { path, ...profile }
}

function selfTest() {
  const manifest = {
    manifest_version: 3,
    name: '__MSG_name__',
    version: '1.0.0',
    description: '__MSG_description__',
    default_locale: 'en',
    permissions: ['storage', 'debugger'],
    host_permissions: ['https://*/*'],
    icons: { 128: 'icon128.png' }
  }
  const files = {
    'manifest.json': JSON.stringify(manifest),
    '_locales/en/messages.json': JSON.stringify({ name: { message: 'Example' }, description: { message: 'Example extension' } }),
    'icon128.png': ''
  }
  const result = inspect({ kind: 'test', path: 'test', entries: Object.keys(files), read: (entry) => files[entry] })
  assert.equal(result.ok, true)
  assert.equal(result.manifest.name, 'Example')
  assert.equal(result.warnings.length, 2)
  console.log('preflight self-test passed')
}

if (target === '--self-test') {
  selfTest()
} else if (!target || (profileFlag !== -1 && !profilePath)) {
  console.error(`Usage: ${basename(process.argv[1])} <extension-directory-or-zip> [--profile publish-profile.json]\n       ${basename(process.argv[1])} --self-test`)
  process.exitCode = 2
} else {
  try {
    const result = inspect(openTarget(target))
    const profile = readProfile(profilePath)
    console.log(JSON.stringify(profile ? { ...result, profile } : result, null, 2))
    if (!result.ok) process.exitCode = 1
  } catch (error) {
    console.error(error.message)
    process.exitCode = 1
  }
}

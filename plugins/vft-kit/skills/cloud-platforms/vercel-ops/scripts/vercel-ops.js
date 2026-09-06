#!/usr/bin/env node

/**
 * vercel-ops - Universal Vercel API Operations CLI
 * Zero dependencies, multi-profile support
 * Node 18+ required
 */

import { readFile, open } from 'fs/promises';
import { homedir } from 'os';
import { join, resolve } from 'path';
import { pathToFileURL } from 'url';

// ============================================================================
// Configuration & Token Management
// ============================================================================

class VercelConfig {
  constructor() {
    this.token = null;
    this.teamId = null;
    this.teamSlug = null;
    this.verbose = false;
  }

  async load(options = {}) {
    const profile = options.profile || 'default';

    const configPath = await this._findConfigFile(options.config);
    const data = configPath ? parseJSON(await readFile(configPath, 'utf-8'), 'config file') : {};
    if (!data || Array.isArray(data) || typeof data !== 'object') throw new Error('Config must be an object');
    const selected = Object.hasOwn(data, profile) ? data[profile] :
      (profile === 'default' && (['access_token', 'team_id', 'team_slug'].some(key => Object.hasOwn(data, key)) || !configPath) ? data : null);
    if (!selected || Array.isArray(selected) || typeof selected !== 'object') throw new Error(`Config profile not found: ${profile}`);
    this.token = process.env.VERCEL_TOKEN || selected.access_token;
    this.teamId = options.teamId || selected.team_id || null;
    this.teamSlug = selected.team_slug;

    if (typeof this.token !== 'string' || !this.token.trim()) {
      throw new Error('VERCEL_TOKEN not found. Set environment variable or create config file.');
    }
  }

  async _findConfigFile(customPath) {
    if (customPath) {
      await readFile(customPath); // Explicit paths must not silently fall back to another account.
      return resolve(customPath);
    }
    const candidates = [
      customPath,
      './vercel-config.json',
      join(homedir(), '.config/vercel/config.json'),
    ].filter(Boolean);

    for (const path of candidates) {
      try {
        await readFile(path);
        return resolve(path);
      } catch {
        continue;
      }
    }
    return null;
  }
}

// ============================================================================
// Vercel API Client
// ============================================================================

class VercelAPI {
  constructor(config) {
    this.config = config;
    this.baseURL = 'https://api.vercel.com';
  }

  async request(method, endpoint, options = {}) {
    if (typeof endpoint !== 'string' || !endpoint.startsWith('/') || endpoint.startsWith('//') || endpoint.includes('\\')) {
      throw new Error('API endpoint must be an absolute path on api.vercel.com');
    }
    const url = new URL(endpoint.startsWith('/') ? endpoint : `/${endpoint}`, this.baseURL);
    if (url.origin !== this.baseURL) throw new Error('API endpoint origin is not allowed');

    // Add team ID to query params if available
    if (this.config.teamId && !url.searchParams.has('teamId')) {
      url.searchParams.set('teamId', this.config.teamId);
    }

    // Add custom query params
    if (options.query) {
      for (const [key, value] of Object.entries(options.query)) {
        url.searchParams.set(key, value);
      }
    }

    const headers = {
      'Authorization': `Bearer ${this.config.token}`,
      'Content-Type': 'application/json',
      ...options.headers,
    };

    const fetchOptions = {
      method,
      headers,
      redirect: 'error',
    };

    if (options.body !== undefined) {
      fetchOptions.body = JSON.stringify(options.body);
    }

    if (this.config.verbose) {
      console.error(`${method} ${url.pathname}`);
    }

    // Reads may retry; a timed-out mutation may already have succeeded remotely.
    let retries = method === 'GET' ? 3 : 1;
    while (retries > 0) {
      try {
        const response = await fetch(url.toString(), { ...fetchOptions, signal: AbortSignal.timeout(30000) });

        if (!response.ok) {
          if (response.status === 429 && retries > 1) {
            // Rate limited, retry with exponential backoff
            const delay = (4 - retries) * 2000;
            if (this.config.verbose) console.error(`Rate limited, retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            retries--;
            continue;
          }

          throw new APIError(`HTTP ${response.status}`, response.status);
        }
        const body = await response.text();
        if (!body.trim()) return null;
        return parseJSON(body, 'API response');
      } catch (err) {
        if (err instanceof APIError) throw err;
        if (retries === 1) {
          if (err instanceof TypeError || /Timeout|Abort/.test(err.name)) {
            throw new NetworkError('Request failed or timed out; check remote state before retrying a write');
          }
          throw err;
        }

        retries--;
        await new Promise(resolve => setTimeout(resolve, 1000));
      }
    }
  }

  get(endpoint, options) {
    return this.request('GET', endpoint, options);
  }

  post(endpoint, body, options = {}) {
    return this.request('POST', endpoint, { ...options, body });
  }

  patch(endpoint, body, options = {}) {
    return this.request('PATCH', endpoint, { ...options, body });
  }

  delete(endpoint, options) {
    return this.request('DELETE', endpoint, options);
  }
}

class APIError extends Error {
  constructor(message, statusCode, details) {
    super(message);
    this.name = 'APIError';
    this.statusCode = statusCode;
    this.details = details;
  }
}

class NetworkError extends Error {}

function parseJSON(text, label = 'JSON') {
  try { return JSON.parse(text); }
  catch { throw new Error(`Invalid ${label}`); }
}

function json(value) { console.log(JSON.stringify(value, null, 2)); }

function required(value, label) {
  if (typeof value !== 'string' || !value) throw new Error(`${label} required`);
  return value;
}

function timestamp(value) {
  if (value === 'now') return Date.now();
  if (/^\d+$/.test(value)) return Number(value);
  const relative = /^(\d+)(s|m|h|d)$/.exec(value);
  const result = relative ? Date.now() - Number(relative[1]) * { s: 1000, m: 60000, h: 3600000, d: 86400000 }[relative[2]] : Date.parse(value);
  if (!Number.isFinite(result)) throw new Error('Time must be epoch milliseconds, ISO date, now, or a duration such as 1h');
  return result;
}

function parseEnv(text) {
  // ponytail: single-line dotenv values only; use JSON for multiline secrets.
  const entries = [];
  for (const [index, raw] of text.split(/\r?\n/).entries()) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const match = /^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/.exec(line);
    if (!match) throw new Error(`Invalid env assignment at line ${index + 1}`);
    let value = match[2];
    if (/^["']/.test(value)) {
      const quoted = /^(["'])(.*?)\1\s*(?:#.*)?$/.exec(value);
      if (!quoted) throw new Error(`Invalid or multiline env value at line ${index + 1}; use a JSON object`);
      value = quoted[2];
    } else value = value.split('#')[0].trim();
    entries.push([match[1], value]);
  }
  return entries;
}

// ============================================================================
// Command Handlers
// ============================================================================

const commands = {
  async verify(api, args) {
    const user = await api.get('/v2/user');
    if (args.json) return json(user);
    console.log('✓ Token is valid');
    console.log(`User: ${user.user?.name || user.user?.username || user.user?.email}`);
    console.log(`ID: ${user.user?.id}`);

    if (api.config.teamId) {
      try {
        const team = await api.get(`/v2/teams/${api.config.teamId}`);
        console.log(`Team: ${team.name} (${team.slug})`);
      } catch (err) {
        console.error('Warning: Could not fetch team info');
      }
    }
  },

  async projects(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const params = { limit: args.limit || 20 };
        const result = await api.get('/v10/projects', { query: params });

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.projects.length} projects:\n`);
          for (const p of result.projects) {
            console.log(`${p.name} (${p.id})`);
            console.log(`  Framework: ${p.framework || 'none'}`);
            console.log(`  Updated: ${new Date(p.updatedAt).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'get': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID or name required');

        const project = await api.get(`/v9/projects/${projectId}`);

        if (args.json) {
          console.log(JSON.stringify(project, null, 2));
        } else {
          console.log(`Project: ${project.name}`);
          console.log(`ID: ${project.id}`);
          console.log(`Framework: ${project.framework || 'none'}`);
          console.log(`Build Command: ${project.buildCommand || 'default'}`);
          console.log(`Output Directory: ${project.outputDirectory || 'default'}`);
          console.log(`Node Version: ${project.nodeVersion || 'default'}`);
          console.log(`Created: ${new Date(project.createdAt).toLocaleString()}`);
          console.log(`Updated: ${new Date(project.updatedAt).toLocaleString()}`);
        }
        break;
      }

      case 'create': {
        required(args.name, '--name');
        const body = {
          name: args.name,
          framework: args.framework,
          buildCommand: args['build-command'],
          outputDirectory: args['output-directory'],
          installCommand: args['install-command'],
          devCommand: args['dev-command'],
          rootDirectory: args['root-directory'],
        };

        // Remove undefined values
        Object.keys(body).forEach(key => body[key] === undefined && delete body[key]);

        const project = await api.post('/v11/projects', body);
        if (args.json) return json(project);
        console.log('✓ Project created');
        console.log(`ID: ${project.id}`);
        console.log(`Name: ${project.name}`);
        break;
      }

      case 'update': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        const body = {
          name: args.name,
          framework: args.framework,
          buildCommand: args['build-command'],
          outputDirectory: args['output-directory'],
          installCommand: args['install-command'],
          devCommand: args['dev-command'],
        };

        Object.keys(body).forEach(key => body[key] === undefined && delete body[key]);

        const project = await api.patch(`/v9/projects/${projectId}`, body);
        if (args.json) return json(project);
        console.log('✓ Project updated');
        break;
      }

      case 'delete': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        await api.delete(`/v9/projects/${projectId}`);
        if (args.json) return json({ deleted: projectId });
        console.log('✓ Project deleted');
        break;
      }

      case 'link': {
        throw new Error('Use vercel link then vercel git connect in the project directory; see references/examples.md');
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async deployments(api, args) {
    const subcommand = args._[1];
    if (args.target && !['production', 'preview'].includes(args.target)) throw new Error('--target must be production or preview');

    switch (subcommand) {
      case 'list': {
        const params = {
          limit: args.limit || 20,
          ...(args.project && { projectId: args.project }),
        };

        const result = await api.get('/v7/deployments', { query: params });

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.deployments.length} deployments:\n`);
          for (const d of result.deployments) {
            const statusEmoji = d.state === 'READY' ? '✓' : d.state === 'ERROR' ? '✗' : '⋯';
            console.log(`${statusEmoji} ${d.url}`);
            console.log(`  ID: ${d.uid}`);
            console.log(`  State: ${d.state}`);
            console.log(`  Created: ${new Date(d.created).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'get': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        const deployment = await api.get(`/v13/deployments/${deploymentId}`);

        if (args.json) {
          console.log(JSON.stringify(deployment, null, 2));
        } else {
          console.log(`Deployment: ${deployment.url}`);
          console.log(`ID: ${deployment.id || deployment.uid}`);
          console.log(`State: ${deployment.readyState}`);
          console.log(`Target: ${deployment.target || 'preview'}`);
          console.log(`Created: ${new Date(deployment.created).toLocaleString()}`);
          if (deployment.ready) {
            console.log(`Ready: ${new Date(deployment.ready).toLocaleString()}`);
          }
        }
        break;
      }

      case 'create': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        // 获取项目的 Git 配置
        const project = await api.get(`/v9/projects/${projectId}`);

        if (!project.link) {
          throw new Error(`Project ${projectId} has no Git integration. Use deploy hooks or link a repository first.`);
        }

        // 构建 Git source
        const gitSource = {
          type: project.link.type,  // "github" | "gitlab" | "bitbucket"
          ...(project.link.type === 'gitlab' ? { projectId: project.link.projectId } :
            project.link.type === 'bitbucket' ? { repoUuid: project.link.uuid, workspaceUuid: project.link.workspaceUuid } :
            { repoId: project.link.repoId }),
          ref: args.ref || project.link.productionBranch || 'main',
        };

        // 允许用户覆盖（高级用法）
        if (args['git-source']) {
          Object.assign(gitSource, parseJSON(args['git-source'], '--git-source'));
        }

        const body = {
          name: project.name,  // 项目名称（必需）
          project: projectId,  // 项目 ID
          ...(args.target === 'production' && { target: 'production' }),
          gitSource: gitSource,
        };

        const deployment = await api.post('/v13/deployments', body);
        if (args.json) return json(deployment);
        console.log('✓ Deployment created');
        console.log(`ID: ${deployment.id}`);
        console.log(`URL: https://${deployment.url}`);
        console.log(`Status: ${deployment.readyState || 'QUEUED'}`);

        break;
      }

      case 'cancel': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        await api.patch(`/v12/deployments/${deploymentId}/cancel`);
        if (args.json) return json({ canceled: deploymentId });
        console.log('✓ Deployment canceled');
        break;
      }

      case 'redeploy': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        const previous = await api.get(`/v13/deployments/${deploymentId}`);
        const body = {
          name: previous.name,
          deploymentId,
          ...(args.target === 'production' && { target: 'production' }),
        };

        const deployment = await api.post('/v13/deployments', body);
        if (args.json) return json(deployment);
        console.log('✓ Redeployment created');
        console.log(`ID: ${deployment.id}`);
        console.log(`URL: ${deployment.url}`);
        break;
      }

      case 'delete': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        await api.delete(`/v13/deployments/${deploymentId}`);
        if (args.json) return json({ deleted: deploymentId });
        console.log('✓ Deployment deleted');
        break;
      }

      case 'wait': {
        const id = required(args._[2], 'Deployment ID');
        const seconds = Number(args.timeout || 1800);
        if (!Number.isFinite(seconds) || seconds <= 0) throw new Error('--timeout must be positive seconds');
        const deadline = Date.now() + seconds * 1000;
        while (Date.now() < deadline) {
          const deployment = await api.get(`/v13/deployments/${id}`);
          const state = deployment.readyState || deployment.state;
          if (state === 'READY') return json(deployment);
          if (['ERROR', 'CANCELED'].includes(state)) throw new Error(`Deployment ${id}: ${state}`);
          if (!args.json) console.error(`${id}: ${state}`);
          await new Promise(resolve => setTimeout(resolve, Math.min(5000, Math.max(0, deadline - Date.now()))));
        }
        throw new Error(`Deployment ${id}: wait timed out`);
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async domains(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const projectId = args.project;
        if (!projectId) throw new Error('--project required');

        const result = await api.get(`/v9/projects/${projectId}/domains`);

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.domains.length} domains:\n`);
          for (const d of result.domains) {
            const verifiedEmoji = d.verified ? '✓' : '✗';
            console.log(`${verifiedEmoji} ${d.name}`);
            console.log(`  Verified: ${d.verified}`);
            console.log(`  Created: ${new Date(d.createdAt).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'add': {
        const projectId = args._[2];
        const domain = args.domain;
        if (!projectId || !domain) throw new Error('Project ID and --domain required');

        const body = { name: domain };
        await api.post(`/v10/projects/${projectId}/domains`, body);
        if (args.json) return json({ projectId, domain });
        console.log(`✓ Domain ${domain} added to project`);
        break;
      }

      case 'verify': {
        const domain = args._[2];
        if (!domain) throw new Error('Domain required');

        const projectId = required(args.project, '--project');
        const result = await api.post(`/v9/projects/${projectId}/domains/${domain}/verify`);

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Domain: ${domain}`);
          console.log(`Verified: ${result.verified ? 'Yes' : 'No'}`);
          if (!result.verified && result.misconfigured) {
            console.log('\nConfiguration issues:');
            console.log(JSON.stringify(result.misconfigured, null, 2));
          }
        }
        break;
      }

      case 'remove': {
        const domain = args._[2];
        if (!domain) throw new Error('Domain required');

        const projectId = required(args.project, '--project');
        await api.delete(`/v9/projects/${projectId}/domains/${domain}`);
        if (args.json) return json({ projectId, removed: domain });
        console.log(`✓ Domain ${domain} removed`);
        break;
      }

      case 'get': {
        const domain = args._[2];
        if (!domain) throw new Error('Domain required');

        const result = await api.get(`/v5/domains/${domain}`);
        console.log(JSON.stringify(result, null, 2));
        break;
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async env(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        const result = await api.get(`/v10/projects/${projectId}/env`);
        for (const env of result.envs || []) delete env.value;

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.envs.length} environment variables:\n`);
          for (const env of result.envs) {
            console.log(`${env.key}`);
            console.log(`  ID: ${env.id}`);
            console.log(`  Target: ${env.target.join(', ')}`);
            console.log(`  Type: ${env.type}`);
            console.log();
          }
        }
        break;
      }

      case 'add': {
        const projectId = args._[2];
        const key = args.key;
        const value = args.value;
        const target = args.target ? args.target.split(',') : ['production', 'preview', 'development'];

        if (!projectId || !key || typeof value !== 'string') {
          throw new Error('Project ID, --key, and --value required');
        }

        const body = {
          key,
          value,
          type: args.type || 'encrypted',
          target,
        };

        await api.post(`/v10/projects/${projectId}/env`, body);
        if (args.json) return json({ added: key });
        console.log(`✓ Environment variable ${key} added`);
        break;
      }

      case 'update': {
        const projectId = args._[2];
        const envId = args._[3];

        if (!projectId || !envId) throw new Error('Project ID and Env ID required');

        const body = {
          ...(typeof args.value === 'string' && { value: args.value }),
          ...(args.target && { target: args.target.split(',') }),
        };

        await api.patch(`/v9/projects/${projectId}/env/${envId}`, body);
        if (args.json) return json({ updated: envId });
        console.log('✓ Environment variable updated');
        break;
      }

      case 'remove': {
        const projectId = args._[2];
        const envId = args._[3];

        if (!projectId || !envId) throw new Error('Project ID and Env ID required');

        await api.delete(`/v9/projects/${projectId}/env/${envId}`);
        if (args.json) return json({ removed: envId });
        console.log('✓ Environment variable removed');
        break;
      }

      case 'import': {
        const projectId = args._[2];
        const file = args.file;
        const target = args.target ? args.target.split(',') : ['production'];

        if (!projectId || !file) throw new Error('Project ID and --file required');

        const envContent = await readFile(file, 'utf-8');
        const entries = file.endsWith('.json') ? Object.entries(parseJSON(envContent, 'env JSON file')) : parseEnv(envContent);
        if (entries.some(([key, value]) => !/^[A-Za-z_][A-Za-z0-9_]*$/.test(key) || typeof value !== 'string')) {
          throw new Error('Environment values must be strings with valid variable names');
        }
        for (const [key, value] of entries) {
          await api.post(`/v10/projects/${projectId}/env`, { key, value, type: 'encrypted', target }, { query: { upsert: 'true' } });
          if (!args.json) console.log(`✓ ${key}`);
        }
        if (args.json) return json({ imported: entries.map(([key]) => key) });
        break;
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async logs(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'get': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        const params = {
          ...(args.since && { since: timestamp(args.since) }),
          ...(args.until && { until: timestamp(args.until) }),
          builds: 1,
          direction: 'backward',
          limit: args.limit || 100,
        };
        if (args.source && args.source !== 'build') throw new Error('logs get returns build logs; use vercel logs for runtime logs');
        const result = await api.get(`/v3/deployments/${deploymentId}/events`, { query: params });

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          for (const event of result || []) {
            const timestamp = new Date(event.created).toISOString();
            console.log(`[${timestamp}] ${event.text || event.payload?.text || ''}`);
          }
        }
        break;
      }

      case 'follow': {
        throw new Error('Build logs: vercel inspect <deployment> --logs --wait. Runtime stream: vercel logs <deployment> --follow');
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async aliases(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const result = await api.get('/v4/aliases', {
          query: { limit: args.limit || 20 }
        });

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.aliases.length} aliases:\n`);
          for (const alias of result.aliases) {
            console.log(`${alias.alias} → ${alias.deploymentId}`);
            console.log(`  Created: ${new Date(alias.createdAt).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'assign': {
        const deploymentId = args._[2];
        const alias = args.alias;

        if (!deploymentId || !alias) throw new Error('Deployment ID and --alias required');

        await api.post(`/v2/deployments/${deploymentId}/aliases`, { alias });
        if (args.json) return json({ deploymentId, alias });
        console.log(`✓ Alias ${alias} assigned to deployment`);
        break;
      }

      case 'remove': {
        const alias = args._[2];
        if (!alias) throw new Error('Alias required');

        await api.delete(`/v2/aliases/${alias}`);
        if (args.json) return json({ removed: alias });
        console.log(`✓ Alias ${alias} removed`);
        break;
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async teams(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const result = await api.get('/v2/teams');

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.teams.length} teams:\n`);
          for (const team of result.teams) {
            console.log(`${team.name} (${team.slug})`);
            console.log(`  ID: ${team.id}`);
            console.log(`  Created: ${new Date(team.created).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'get': {
        const teamId = args._[2];
        if (!teamId) throw new Error('Team ID required');

        const team = await api.get(`/v2/teams/${teamId}`);
        console.log(JSON.stringify(team, null, 2));
        break;
      }

      case 'members': {
        const teamId = args._[2];
        if (!teamId) throw new Error('Team ID required');

        const result = await api.get(`/v3/teams/${teamId}/members`);

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`Found ${result.members.length} members:\n`);
          for (const member of result.members) {
            console.log(`${member.username} (${member.role})`);
            console.log(`  Email: ${member.email}`);
            console.log(`  Joined: ${new Date(member.created).toLocaleString()}`);
            console.log();
          }
        }
        break;
      }

      case 'invite': {
        const teamId = args._[2];
        const email = args.email;
        const role = args.role || 'MEMBER';

        if (!teamId || !email) throw new Error('Team ID and --email required');

        await api.post(`/v2/teams/${teamId}/members`, { email, role });
        if (args.json) return json({ invited: email, teamId });
        console.log(`✓ Invitation sent to ${email}`);
        break;
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async api(api, args) {
    const method = args._[1]?.toUpperCase();
    const endpoint = args._[2];

    if (!method || !endpoint) {
      throw new Error('Usage: api <METHOD> <ENDPOINT> [--data <json>] [--query <params>]');
    }

    const options = {};

    if (!['GET', 'POST', 'PATCH', 'PUT', 'DELETE', 'HEAD'].includes(method)) throw new Error('Unsupported HTTP method');
    if (args.data !== undefined && args['data-file']) throw new Error('Use either --data or --data-file');
    if (args.data) {
      options.body = parseJSON(args.data, '--data');
    }
    if (args['data-file']) options.body = parseJSON(await readFile(args['data-file'], 'utf8'), '--data-file');

    if (args.query) {
      options.query = Object.fromEntries(new URLSearchParams(args.query));
    }

    const result = await api.request(method, endpoint, options);
    console.log(JSON.stringify(result, null, 2));
  },
};

commands['edge-config'] = async (api, args) => {
  // Current official OpenAPI calls the control-plane resource global-config.
  const base = '/v1/global-config';
  const sub = args._[1];
  if (sub === 'list') return json(await api.get(base));
  if (sub === 'create') return json(await api.post(base, { slug: required(args.name, '--name') }));
  const id = encodeURIComponent(required(args._[2], 'Edge Config ID'));
  const key = args.key && encodeURIComponent(args.key);
  if (sub === 'get') return json(await api.get(`${base}/${id}/${key ? `item/${key}` : 'items'}`));
  let items;
  if (sub === 'set' || sub === 'delete') {
    required(args.key, '--key');
    items = [{ operation: sub === 'set' ? 'upsert' : 'delete', key: args.key,
      ...(sub === 'set' && { value: parseJSON(required(args.value, '--value (JSON)'), '--value') }) }];
  } else if (sub === 'update') {
    const values = parseJSON(await readFile(required(args.file, '--file'), 'utf8'), 'Edge Config file');
    if (!values || Array.isArray(values) || typeof values !== 'object') throw new Error('Edge Config file must contain an object of key/value pairs');
    items = Object.entries(values).map(([key, value]) => ({ operation: 'upsert', key, value }));
  } else throw new Error(`Unknown edge-config subcommand: ${sub}`);
  if (items.some(item => !/^[\w-]{1,256}$/.test(item.key))) throw new Error('Invalid Edge Config key');
  json(await api.patch(`${base}/${id}/items`, { items }));
};

commands.webhooks = async (api, args) => {
  const sub = args._[1];
  if (sub === 'list') {
    const result = await api.get('/v1/webhooks', { query: args.project ? { projectId: args.project } : {} });
    for (const webhook of Array.isArray(result) ? result : result.webhooks || []) delete webhook.secret;
    return json(result);
  }
  if (sub === 'create') {
    const url = new URL(required(args.url, '--url'));
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('Webhook URL must be HTTP(S) without credentials');
    const events = required(args.events, '--events').split(',').filter(Boolean);
    if (!events.length) throw new Error('--events must not be empty');
    // Reserve the destination before creating a remote resource; never overwrite a secret.
    const file = await open(required(args['secret-file'], '--secret-file'), 'wx', 0o600);
    try {
      const result = await api.post('/v1/webhooks', { url: url.href, events,
        ...(args.project && { projectIds: args.project.split(',') }) });
      if (!result.secret) throw new Error('Webhook created but no signing secret returned; inspect webhooks before retrying');
      await file.writeFile(result.secret);
      delete result.secret;
      return json(result);
    } finally { await file.close(); }
  }
  const id = encodeURIComponent(required(args._[2], 'Webhook ID'));
  if (sub === 'get') {
    const result = await api.get(`/v1/webhooks/${id}`);
    delete result.secret;
    return json(result);
  }
  if (sub === 'delete') { await api.delete(`/v1/webhooks/${id}`); return json({ deleted: args._[2] }); }
  throw new Error('Supported webhook commands: list, create, get, delete. No public test endpoint is assumed.');
};

// ============================================================================
// CLI Parser
// ============================================================================

function parseArgs(argv) {
  const args = { _: [] };
  const flags = new Set(['json', 'verbose', 'help']);
  const values = new Set(['profile', 'config', 'team-id', 'limit', 'name', 'framework', 'build-command',
    'output-directory', 'install-command', 'dev-command', 'root-directory', 'repo', 'branch', 'project',
    'ref', 'git-source', 'target', 'domain', 'key', 'value', 'type', 'file', 'since', 'until', 'source',
    'alias', 'email', 'role', 'data', 'data-file', 'query', 'timeout', 'url', 'events', 'secret-file']);

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i] === '-h' ? '--help' : argv[i];

    if (arg.startsWith('--')) {
      const separator = arg.indexOf('=');
      const key = arg.slice(2, separator < 0 ? undefined : separator);
      if (flags.has(key)) {
        if (separator >= 0) throw new Error(`--${key} does not take a value`);
        args[key] = true;
        continue;
      }
      if (!values.has(key)) throw new Error(`Unknown option: --${key}`);
      if (separator >= 0) { args[key] = arg.slice(separator + 1); continue; }
      const value = argv[i + 1];

      if (value && !value.startsWith('--')) {
        args[key] = value;
        i++;
      } else {
        throw new Error(`--${key} requires a value`);
      }
    } else if (arg.startsWith('-')) {
      throw new Error(`Unknown option: ${arg}`);
    } else {
      args._.push(arg);
    }
  }

  return args;
}

// ============================================================================
// Main
// ============================================================================

async function main() {
  let args = {};
  try {
  args = parseArgs(process.argv.slice(2));

  if (args._.length === 0 || args.help || args.h) {
    console.log(`
vercel-ops - Universal Vercel API Operations CLI

Usage: node vercel-ops.js <command> <subcommand> [options]

Commands:
  verify          Verify token and show account info
  projects        Manage projects (list, get, create, update, delete)
  deployments     Manage deployments (list, get, create, cancel, redeploy, delete, wait)
  domains         Manage domains (list, add, verify, remove, get)
  env             Manage environment variables (list, add, update, remove, import)
  logs            Query build logs (get); runtime/follow: use official vercel CLI
  aliases         Manage aliases (list, assign, remove)
  teams           Manage teams (list, get, members, invite)
  edge-config     Manage Edge Config (list, create, get, set, delete, update)
  webhooks        Manage webhooks (list, create, get, delete)
  api             Direct API call (GET/POST/PATCH/DELETE <endpoint>)

Global Options:
  --profile <name>    Use specific profile (default: "default")
  --config <path>     Path to config file
  --team-id <id>      Override team ID
  --json              Output raw JSON
  --verbose           Show detailed logs
  --help, -h          Show this help

Examples:
  node vercel-ops.js verify
  node vercel-ops.js projects list
  node vercel-ops.js deployments create my-project --target production
  node vercel-ops.js env add prj_xxx --key API_KEY --value secret --target production
  node vercel-ops.js api GET /v9/projects --query "limit=10"

Environment Variables:
  VERCEL_TOKEN        Vercel access token (highest priority)

For detailed documentation, see SKILL.md
`);
    return;
  }

    const command = args._[0];
    const native = {
      blob: 'vercel blob --help (Blob uses a separate store token; see references/examples.md)',
      functions: 'vercel inspect <deployment> or vercel logs <deployment>',
      crons: 'edit crons in vercel.json, then deploy; see references/examples.md',
      monitoring: 'vercel metrics schema, then vercel metrics <metric-id>',
    };
    if (native[command]) throw new Error(`Use the official workflow: ${native[command]}`);
    if (!Object.hasOwn(commands, command)) throw new Error(`Unknown command: ${command}. Run with --help.`);
    if (command !== 'api' && args._.slice(2).some(value => /[/?#\\]/.test(value) || value === '.' || value === '..')) {
      throw new Error('Resource identifiers must be IDs/names, not URLs or paths');
    }
    const config = new VercelConfig();
    config.verbose = args.verbose;

    await config.load({
      profile: args.profile,
      config: args.config,
      teamId: args['team-id'],
    });

    const api = new VercelAPI(config);
    await commands[command](api, args);

  } catch (err) {
    if (err instanceof APIError) {
      console.error(`API Error (${err.statusCode}): ${err.message}`);
      process.exitCode = 2;
    } else {
      console.error(`Error: ${err.message}`);
      process.exitCode = err instanceof NetworkError ? 3 : 1;
    }
  }
}

export { VercelConfig, VercelAPI, commands, parseArgs, parseEnv, timestamp };
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) main();

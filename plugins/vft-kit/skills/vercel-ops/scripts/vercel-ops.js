#!/usr/bin/env node

/**
 * vercel-ops - Universal Vercel API Operations CLI
 * Zero dependencies, multi-profile support
 * Node 18+ required
 */

import { readFile } from 'fs/promises';
import { homedir } from 'os';
import { join, resolve } from 'path';

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

    // 1. Try environment variable (highest priority)
    this.token = process.env.VERCEL_TOKEN;

    // 2. Try config file
    if (!this.token) {
      const configPath = await this._findConfigFile(options.config);
      if (configPath) {
        try {
          const configData = JSON.parse(await readFile(configPath, 'utf-8'));
          const profileConfig = configData[profile] || configData;

          this.token = profileConfig.access_token;
          this.teamId = profileConfig.team_id || options.teamId;
          this.teamSlug = profileConfig.team_slug;

          if (this.verbose) {
            console.error(`Loaded config from: ${configPath}`);
            console.error(`Profile: ${profile}`);
          }
        } catch (err) {
          if (this.verbose) console.error(`Failed to load config: ${err.message}`);
        }
      }
    }

    // Override with CLI options
    if (options.teamId) this.teamId = options.teamId;

    if (!this.token) {
      throw new Error('VERCEL_TOKEN not found. Set environment variable or create config file.');
    }
  }

  async _findConfigFile(customPath) {
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
    const url = new URL(endpoint.startsWith('/') ? endpoint : `/${endpoint}`, this.baseURL);

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
    };

    if (options.body) {
      fetchOptions.body = JSON.stringify(options.body);
    }

    if (this.config.verbose) {
      console.error(`${method} ${url.toString()}`);
      if (options.body) console.error('Body:', JSON.stringify(options.body, null, 2));
    }

    let retries = 3;
    while (retries > 0) {
      try {
        const response = await fetch(url.toString(), fetchOptions);
        const data = await response.json().catch(() => ({}));

        if (!response.ok) {
          if (response.status === 429 && retries > 1) {
            // Rate limited, retry with exponential backoff
            const delay = (4 - retries) * 2000;
            if (this.config.verbose) console.error(`Rate limited, retrying in ${delay}ms...`);
            await new Promise(resolve => setTimeout(resolve, delay));
            retries--;
            continue;
          }

          throw new APIError(data.error?.message || `HTTP ${response.status}`, response.status, data.error);
        }

        return data;
      } catch (err) {
        if (err instanceof APIError) throw err;
        if (retries === 1) throw err;

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

// ============================================================================
// Command Handlers
// ============================================================================

const commands = {
  async verify(api, args) {
    const user = await api.get('/v2/user');
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
        const result = await api.get('/v9/projects', { query: params });

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

        const project = await api.post('/v9/projects', body);
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
        console.log('✓ Project updated');
        break;
      }

      case 'delete': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        await api.delete(`/v9/projects/${projectId}`);
        console.log('✓ Project deleted');
        break;
      }

      case 'link': {
        const projectId = args._[2];
        if (!projectId) throw new Error('Project ID required');

        const body = {
          type: 'github',
          repo: args.repo,
          ...(args.branch && { productionBranch: args.branch }),
        };

        await api.post(`/v9/projects/${projectId}/link`, body);
        console.log('✓ Git repository linked');
        break;
      }

      default:
        throw new Error(`Unknown subcommand: ${subcommand}`);
    }
  },

  async deployments(api, args) {
    const subcommand = args._[1];

    switch (subcommand) {
      case 'list': {
        const params = {
          limit: args.limit || 20,
          ...(args.project && { projectId: args.project }),
        };

        const result = await api.get('/v6/deployments', { query: params });

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
          console.log(`ID: ${deployment.uid}`);
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

        const body = {
          name: projectId,
          target: args.target || 'preview',
          ...(args['git-source'] && { gitSource: JSON.parse(args['git-source']) }),
        };

        const deployment = await api.post('/v13/deployments', body);
        console.log('✓ Deployment created');
        console.log(`ID: ${deployment.id}`);
        console.log(`URL: ${deployment.url}`);
        break;
      }

      case 'cancel': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        await api.patch(`/v12/deployments/${deploymentId}/cancel`);
        console.log('✓ Deployment canceled');
        break;
      }

      case 'redeploy': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        const body = {
          deploymentId,
          target: args.target || 'preview',
        };

        const deployment = await api.post('/v13/deployments', body);
        console.log('✓ Redeployment created');
        console.log(`ID: ${deployment.id}`);
        console.log(`URL: ${deployment.url}`);
        break;
      }

      case 'delete': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        await api.delete(`/v13/deployments/${deploymentId}`);
        console.log('✓ Deployment deleted');
        break;
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
        console.log(`✓ Domain ${domain} added to project`);
        break;
      }

      case 'verify': {
        const domain = args._[2];
        if (!domain) throw new Error('Domain required');

        const result = await api.get(`/v6/domains/${domain}/config`);

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

        await api.delete(`/v6/domains/${domain}`);
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

        const result = await api.get(`/v9/projects/${projectId}/env`);

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

        if (!projectId || !key || !value) {
          throw new Error('Project ID, --key, and --value required');
        }

        const body = {
          key,
          value,
          type: args.type || 'encrypted',
          target,
        };

        await api.post(`/v10/projects/${projectId}/env`, body);
        console.log(`✓ Environment variable ${key} added`);
        break;
      }

      case 'update': {
        const projectId = args._[2];
        const envId = args._[3];

        if (!projectId || !envId) throw new Error('Project ID and Env ID required');

        const body = {
          ...(args.value && { value: args.value }),
          ...(args.target && { target: args.target.split(',') }),
        };

        await api.patch(`/v9/projects/${projectId}/env/${envId}`, body);
        console.log('✓ Environment variable updated');
        break;
      }

      case 'remove': {
        const projectId = args._[2];
        const envId = args._[3];

        if (!projectId || !envId) throw new Error('Project ID and Env ID required');

        await api.delete(`/v9/projects/${projectId}/env/${envId}`);
        console.log('✓ Environment variable removed');
        break;
      }

      case 'import': {
        const projectId = args._[2];
        const file = args.file;
        const target = args.target ? args.target.split(',') : ['production'];

        if (!projectId || !file) throw new Error('Project ID and --file required');

        const envContent = await readFile(file, 'utf-8');
        const lines = envContent.split('\n').filter(line => line.trim() && !line.startsWith('#'));

        for (const line of lines) {
          const [key, ...valueParts] = line.split('=');
          const value = valueParts.join('=').trim();

          try {
            await api.post(`/v10/projects/${projectId}/env`, {
              key: key.trim(),
              value,
              type: 'encrypted',
              target,
            });
            console.log(`✓ ${key.trim()}`);
          } catch (err) {
            console.error(`✗ ${key.trim()}: ${err.message}`);
          }
        }
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
          ...(args.since && { since: args.since }),
          ...(args.until && { until: args.until }),
          ...(args.source && { source: args.source }),
          limit: args.limit || 100,
        };

        const result = await api.get(`/v2/deployments/${deploymentId}/events`, { query: params });

        if (args.json) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          for (const event of result) {
            const timestamp = new Date(event.created).toISOString();
            console.log(`[${timestamp}] ${event.text || event.payload?.text || ''}`);
          }
        }
        break;
      }

      case 'follow': {
        const deploymentId = args._[2];
        if (!deploymentId) throw new Error('Deployment ID required');

        console.log('Following logs (Ctrl+C to stop)...\n');

        let lastTimestamp = Date.now();
        while (true) {
          const result = await api.get(`/v2/deployments/${deploymentId}/events`, {
            query: { since: lastTimestamp, limit: 100 }
          });

          for (const event of result) {
            const timestamp = new Date(event.created).toISOString();
            console.log(`[${timestamp}] ${event.text || event.payload?.text || ''}`);
            lastTimestamp = Math.max(lastTimestamp, event.created);
          }

          await new Promise(resolve => setTimeout(resolve, 2000));
        }
        break;
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
        console.log(`✓ Alias ${alias} assigned to deployment`);
        break;
      }

      case 'remove': {
        const alias = args._[2];
        if (!alias) throw new Error('Alias required');

        await api.delete(`/v2/aliases/${alias}`);
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

        const result = await api.get(`/v2/teams/${teamId}/members`);

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

        await api.post(`/v1/teams/${teamId}/members`, { email, role });
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

    if (args.data) {
      options.body = JSON.parse(args.data);
    }

    if (args.query) {
      options.query = Object.fromEntries(
        args.query.split('&').map(p => p.split('='))
      );
    }

    const result = await api.request(method, endpoint, options);
    console.log(JSON.stringify(result, null, 2));
  },
};

// Add placeholders for remaining commands
['edge-config', 'blob', 'functions', 'crons', 'webhooks', 'monitoring'].forEach(cmd => {
  commands[cmd] = async (api, args) => {
    console.log(`\n⚠️  Command "${cmd}" not yet implemented.`);
    console.log(`This is a placeholder. The full implementation will include:`);

    const features = {
      'edge-config': ['list', 'create', 'get', 'set', 'delete', 'update'],
      'blob': ['list', 'create', 'put', 'get', 'delete', 'list-keys'],
      'functions': ['list', 'get', 'logs', 'invoke'],
      'crons': ['list', 'create', 'update', 'delete', 'trigger'],
      'webhooks': ['list', 'create', 'delete', 'test'],
      'monitoring': ['analytics', 'bandwidth', 'build-time', 'errors'],
    };

    console.log(`  Subcommands: ${features[cmd].join(', ')}`);
    console.log(`\nFeel free to implement this using the "api" command or extend this script.\n`);
  };
});

// ============================================================================
// CLI Parser
// ============================================================================

function parseArgs(argv) {
  const args = { _: [] };

  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];

    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      const value = argv[i + 1];

      if (value && !value.startsWith('--')) {
        args[key] = value;
        i++;
      } else {
        args[key] = true;
      }
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
  const args = parseArgs(process.argv.slice(2));

  if (args._.length === 0 || args.help || args.h) {
    console.log(`
vercel-ops - Universal Vercel API Operations CLI

Usage: node vercel-ops.js <command> <subcommand> [options]

Commands:
  verify          Verify token and show account info
  projects        Manage projects (list, get, create, update, delete, link)
  deployments     Manage deployments (list, get, create, cancel, redeploy, delete)
  domains         Manage domains (list, add, verify, remove, get)
  env             Manage environment variables (list, add, update, remove, import)
  logs            Query deployment logs (get, follow)
  aliases         Manage aliases (list, assign, remove)
  teams           Manage teams (list, get, members, invite)
  edge-config     Manage Edge Config [coming soon]
  blob            Manage Blob storage [coming soon]
  functions       Manage Serverless Functions [coming soon]
  crons           Manage Cron Jobs [coming soon]
  webhooks        Manage webhooks [coming soon]
  monitoring      Query monitoring data [coming soon]
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
    process.exit(0);
  }

  try {
    const config = new VercelConfig();
    config.verbose = args.verbose;

    await config.load({
      profile: args.profile,
      config: args.config,
      teamId: args['team-id'],
    });

    const api = new VercelAPI(config);
    const command = args._[0];

    if (!commands[command]) {
      throw new Error(`Unknown command: ${command}. Run with --help to see available commands.`);
    }

    await commands[command](api, args);

  } catch (err) {
    if (err instanceof APIError) {
      console.error(`API Error (${err.statusCode}): ${err.message}`);
      if (err.details) {
        console.error('Details:', JSON.stringify(err.details, null, 2));
      }
      process.exit(2);
    } else {
      console.error(`Error: ${err.message}`);
      if (args.verbose) console.error(err.stack);
      process.exit(1);
    }
  }
}

main();

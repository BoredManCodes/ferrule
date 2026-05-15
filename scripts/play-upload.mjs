#!/usr/bin/env node
// Upload an Android App Bundle (.aab) to the Google Play Console.
//
// Auth (chosen automatically):
//   - PLAY_OAUTH_CLIENT (path to OAuth desktop-app client JSON)        -- "Plan B"
//   - PLAY_SERVICE_ACCOUNT_JSON (path to service-account key JSON)     -- "Plan A"
//
// Usage:
//   node play-upload.mjs --aab <path> [--track internal] [--package au.com.bordertechsolutions.ferrule]
//                        [--notes <file>] [--notes-text "..."] [--language en-AU]
//                        [--name <release name>] [--status completed]
//                        [--service-account <path>] [--oauth-client <path>]

import { spawn } from 'node:child_process';
import {
  createReadStream,
  existsSync,
  readFileSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import http from 'node:http';
import { createServer as createNetServer } from 'node:net';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { OAuth2Client } from 'google-auth-library';
import { google } from 'googleapis';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCOPES = ['https://www.googleapis.com/auth/androidpublisher'];
const TOKEN_PATH = resolve(__dirname, '.oauth-token.json');

function parseArgs(argv) {
  const args = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        args[key] = next;
        i++;
      } else {
        args[key] = true;
      }
    } else {
      args._.push(a);
    }
  }
  return args;
}

function freePort() {
  return new Promise((res, rej) => {
    const srv = createNetServer();
    srv.unref();
    srv.on('error', rej);
    srv.listen(0, () => {
      const port = srv.address().port;
      srv.close(() => res(port));
    });
  });
}

function openBrowser(url) {
  try {
    if (process.platform === 'win32') {
      spawn('cmd', ['/c', 'start', '""', url], {
        detached: true,
        stdio: 'ignore',
      }).unref();
    } else if (process.platform === 'darwin') {
      spawn('open', [url], { detached: true, stdio: 'ignore' }).unref();
    } else {
      spawn('xdg-open', [url], { detached: true, stdio: 'ignore' }).unref();
    }
  } catch {
    // Falls back to manual paste from console output.
  }
}

async function getOAuthClient(clientPath) {
  const cfg = JSON.parse(readFileSync(clientPath, 'utf8'));
  const block = cfg.installed || cfg.web;
  if (!block) {
    throw new Error(
      `OAuth client config at ${clientPath} has no 'installed' or 'web' block`,
    );
  }
  const { client_id, client_secret } = block;

  const persistTokens = (existing, fresh) => {
    const merged = { ...existing, ...fresh };
    writeFileSync(TOKEN_PATH, JSON.stringify(merged, null, 2));
  };

  if (existsSync(TOKEN_PATH)) {
    try {
      const tokens = JSON.parse(readFileSync(TOKEN_PATH, 'utf8'));
      const client = new OAuth2Client(client_id, client_secret);
      client.setCredentials(tokens);
      client.on('tokens', (t) => persistTokens(tokens, t));
      return client;
    } catch (e) {
      console.warn(
        `[oauth] cached token unreadable (${e.message}); re-authenticating...`,
      );
    }
  }

  const port = await freePort();
  const redirectUri = `http://localhost:${port}`;
  const client = new OAuth2Client(client_id, client_secret, redirectUri);
  const authUrl = client.generateAuthUrl({
    access_type: 'offline',
    scope: SCOPES,
    prompt: 'consent',
  });

  console.log('[oauth] opening browser for Google consent...');
  console.log(`[oauth] if it doesn't open, paste this URL manually:\n  ${authUrl}\n`);
  openBrowser(authUrl);

  const code = await new Promise((resolveP, rejectP) => {
    const server = http.createServer((req, res) => {
      try {
        const url = new URL(req.url, redirectUri);
        const error = url.searchParams.get('error');
        const codeParam = url.searchParams.get('code');
        if (error) {
          res.end(`Auth error: ${error}. You can close this tab.`);
          server.close();
          rejectP(new Error(`OAuth error: ${error}`));
          return;
        }
        if (codeParam) {
          res.end('Authorized! You can close this tab.');
          server.close();
          resolveP(codeParam);
          return;
        }
        res.end('Waiting for OAuth callback...');
      } catch (e) {
        rejectP(e);
      }
    });
    server.on('error', rejectP);
    server.listen(port);
    setTimeout(() => {
      try { server.close(); } catch {}
      rejectP(new Error('OAuth timed out after 5 minutes'));
    }, 5 * 60 * 1000);
  });

  const { tokens } = await client.getToken(code);
  if (!tokens.refresh_token) {
    console.warn(
      '[oauth] no refresh_token returned. Revoke prior consent at https://myaccount.google.com/permissions and re-run to force consent.',
    );
  }
  client.setCredentials(tokens);
  writeFileSync(TOKEN_PATH, JSON.stringify(tokens, null, 2));
  console.log(`[oauth] tokens saved to ${TOKEN_PATH}`);
  client.on('tokens', (t) => persistTokens(tokens, t));
  return client;
}

async function getAuth(args) {
  const oauthClient = args['oauth-client']
    ? String(args['oauth-client'])
    : process.env.PLAY_OAUTH_CLIENT;
  if (oauthClient) {
    if (!statSync(oauthClient, { throwIfNoEntry: false })?.isFile()) {
      throw new Error(`OAuth client JSON not found at ${oauthClient}`);
    }
    return getOAuthClient(resolve(oauthClient));
  }
  const saPath = args['service-account']
    ? String(args['service-account'])
    : process.env.PLAY_SERVICE_ACCOUNT_JSON;
  if (saPath) {
    if (!statSync(saPath, { throwIfNoEntry: false })?.isFile()) {
      throw new Error(`Service account JSON not found at ${saPath}`);
    }
    return new google.auth.GoogleAuth({ keyFile: saPath, scopes: SCOPES });
  }
  throw new Error(
    'No auth configured. Set PLAY_OAUTH_CLIENT (Plan B) or PLAY_SERVICE_ACCOUNT_JSON (Plan A).',
  );
}

const args = parseArgs(process.argv.slice(2));

const aabPath = resolve(
  args.aab ||
    join(__dirname, '..', 'build', 'app', 'outputs', 'bundle', 'release', 'app-release.aab'),
);
const track = String(args.track || 'internal');
const packageName = String(args.package || 'au.com.bordertechsolutions.ferrule');
const releaseStatus = String(args.status || 'completed');
const language = String(args.language || 'en-AU');
const releaseName = args.name ? String(args.name) : null;
const notesPath = args.notes ? resolve(String(args.notes)) : null;
const notesText = args['notes-text'] ? String(args['notes-text']) : null;

if (!statSync(aabPath, { throwIfNoEntry: false })?.isFile()) {
  console.error(`ERROR: AAB not found at ${aabPath}`);
  process.exit(1);
}

let releaseNotes = '';
if (notesText) {
  releaseNotes = notesText.trim();
} else if (notesPath) {
  try {
    releaseNotes = readFileSync(notesPath, 'utf8').trim();
  } catch (e) {
    console.warn(`WARN: could not read notes file at ${notesPath}: ${e.message}`);
  }
}
if (releaseNotes.length > 500) {
  releaseNotes = releaseNotes.slice(0, 497).trimEnd() + '…';
}

const auth = await getAuth(args);
const androidpublisher = google.androidpublisher({ version: 'v3', auth });

console.log(`[play-upload] package=${packageName} track=${track} status=${releaseStatus}`);
console.log(`[play-upload] aab=${aabPath}`);
console.log(`[play-upload] notes (${releaseNotes.length} chars):`);
console.log(
  releaseNotes
    ? releaseNotes.split('\n').map((l) => '  ' + l).join('\n')
    : '  (none)',
);

const editRes = await androidpublisher.edits.insert({ packageName, requestBody: {} });
const editId = editRes.data.id;
console.log(`[play-upload] edit ${editId} created`);

try {
  const aabSize = statSync(aabPath).size;
  console.log(`[play-upload] uploading ${(aabSize / 1024 / 1024).toFixed(1)} MiB...`);
  const uploadRes = await androidpublisher.edits.bundles.upload({
    packageName,
    editId,
    media: {
      mimeType: 'application/octet-stream',
      body: createReadStream(aabPath),
    },
  });
  const versionCode = uploadRes.data.versionCode;
  const sha256 = uploadRes.data.sha256;
  console.log(`[play-upload] uploaded versionCode=${versionCode} sha256=${sha256}`);

  await androidpublisher.edits.tracks.update({
    packageName,
    editId,
    track,
    requestBody: {
      track,
      releases: [
        {
          name: releaseName || String(versionCode),
          status: releaseStatus,
          versionCodes: [String(versionCode)],
          releaseNotes: releaseNotes ? [{ language, text: releaseNotes }] : [],
        },
      ],
    },
  });
  console.log(`[play-upload] assigned versionCode ${versionCode} to track '${track}'`);

  await androidpublisher.edits.commit({ packageName, editId });
  console.log(`[play-upload] edit committed → live in Play Console`);
} catch (err) {
  console.error('[play-upload] upload failed; rolling back edit...');
  try {
    await androidpublisher.edits.delete({ packageName, editId });
  } catch (delErr) {
    console.error('[play-upload] rollback failed:', delErr?.message || delErr);
  }
  throw err;
}

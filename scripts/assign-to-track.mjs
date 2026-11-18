#!/usr/bin/env node
// Assign an already-uploaded versionCode to a Play Console track without
// re-uploading the AAB. Useful when a build already lives on Internal and
// you also want it on Closed Testing (alpha) — Play rejects a fresh upload
// of the same versionCode, so this is the cleanest path.
//
// Usage:
//   node assign-to-track.mjs --version-code 9 --track alpha --name 1.1.0 \
//                            --notes <path> [--status draft] [--language en-AU]
//                            [--package au.com.bordertechsolutions.ferrule]
//
// Auth (chosen automatically), same as play-upload.mjs:
//   - PLAY_OAUTH_CLIENT (path to OAuth desktop-app client JSON)        -- Plan B
//   - PLAY_SERVICE_ACCOUNT_JSON (path to service-account key JSON)     -- Plan A

import { existsSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
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

function getOAuthClient(clientPath) {
  const cfg = JSON.parse(readFileSync(clientPath, 'utf8'));
  const block = cfg.installed || cfg.web;
  if (!block) throw new Error(`OAuth client at ${clientPath} has no installed/web block`);
  const { client_id, client_secret } = block;
  if (!existsSync(TOKEN_PATH)) {
    throw new Error(`No cached token at ${TOKEN_PATH}; run play-upload.mjs once to authorise.`);
  }
  const tokens = JSON.parse(readFileSync(TOKEN_PATH, 'utf8'));
  const client = new OAuth2Client(client_id, client_secret);
  client.setCredentials(tokens);
  client.on('tokens', (t) => writeFileSync(TOKEN_PATH, JSON.stringify({ ...tokens, ...t }, null, 2)));
  return client;
}

function getAuth(args) {
  const oauthClient = args['oauth-client'] || process.env.PLAY_OAUTH_CLIENT;
  if (oauthClient) {
    if (!statSync(oauthClient, { throwIfNoEntry: false })?.isFile()) {
      throw new Error(`OAuth client JSON not found at ${oauthClient}`);
    }
    return getOAuthClient(resolve(oauthClient));
  }
  const saPath = args['service-account'] || process.env.PLAY_SERVICE_ACCOUNT_JSON;
  if (saPath) {
    if (!statSync(saPath, { throwIfNoEntry: false })?.isFile()) {
      throw new Error(`Service account JSON not found at ${saPath}`);
    }
    return new google.auth.GoogleAuth({ keyFile: saPath, scopes: SCOPES });
  }
  throw new Error('No auth configured. Set PLAY_OAUTH_CLIENT or PLAY_SERVICE_ACCOUNT_JSON.');
}

const args = parseArgs(process.argv.slice(2));
const versionCode = String(args['version-code'] || '');
const track = String(args.track || 'alpha');
const packageName = String(args.package || 'au.com.bordertechsolutions.ferrule');
const releaseStatus = String(args.status || 'draft');
const language = String(args.language || 'en-AU');
const releaseName = args.name ? String(args.name) : versionCode;
const notesPath = args.notes ? resolve(String(args.notes)) : null;
const notesText = args['notes-text'] ? String(args['notes-text']) : null;

if (!versionCode) {
  console.error('Missing --version-code <N>');
  process.exit(2);
}

let releaseNotes = '';
if (notesText) {
  releaseNotes = notesText.trim();
} else if (notesPath) {
  try { releaseNotes = readFileSync(notesPath, 'utf8').trim(); }
  catch (e) { console.warn(`WARN: could not read notes file at ${notesPath}: ${e.message}`); }
}
if (releaseNotes.length > 500) {
  releaseNotes = releaseNotes.slice(0, 497).trimEnd() + '…';
}

const auth = await getAuth(args);
const androidpublisher = google.androidpublisher({ version: 'v3', auth });

console.log(`[assign] package=${packageName} track=${track} versionCode=${versionCode} status=${releaseStatus}`);
console.log(`[assign] notes (${releaseNotes.length} chars):`);
console.log(releaseNotes ? releaseNotes.split('\n').map((l) => '  ' + l).join('\n') : '  (none)');

const editRes = await androidpublisher.edits.insert({ packageName, requestBody: {} });
const editId = editRes.data.id;
console.log(`[assign] edit ${editId} created`);

try {
  await androidpublisher.edits.tracks.update({
    packageName,
    editId,
    track,
    requestBody: {
      track,
      releases: [
        {
          name: releaseName,
          status: releaseStatus,
          versionCodes: [versionCode],
          releaseNotes: releaseNotes ? [{ language, text: releaseNotes }] : [],
        },
      ],
    },
  });
  console.log(`[assign] assigned versionCode ${versionCode} to track '${track}' (${releaseStatus})`);

  await androidpublisher.edits.commit({ packageName, editId });
  console.log(`[assign] edit committed → visible in Play Console`);
} catch (err) {
  console.error(`[assign] failed: ${err.message}; rolling back edit...`);
  try { await androidpublisher.edits.delete({ packageName, editId }); } catch {}
  throw err;
}

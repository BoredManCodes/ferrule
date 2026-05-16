#!/usr/bin/env node
// Read-only: list what's currently on each Play track for the Ferrule app.
// Uses the same OAuth flow as play-upload.mjs (PLAY_OAUTH_CLIENT env var).

import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { OAuth2Client } from 'google-auth-library';
import { google } from 'googleapis';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SCOPES = ['https://www.googleapis.com/auth/androidpublisher'];
const TOKEN_PATH = resolve(__dirname, '.oauth-token.json');

const packageName = process.argv[2] || 'au.com.bordertechsolutions.ferrule';
const tracks = ['internal', 'alpha', 'beta', 'production'];

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
  client.on('tokens', (t) => {
    writeFileSync(TOKEN_PATH, JSON.stringify({ ...tokens, ...t }, null, 2));
  });
  return client;
}

const oauthClientPath = process.env.PLAY_OAUTH_CLIENT;
if (!oauthClientPath) throw new Error('PLAY_OAUTH_CLIENT env var not set');
const auth = getOAuthClient(oauthClientPath);
const androidpublisher = google.androidpublisher({ version: 'v3', auth });

console.log(`[inspect] package ${packageName}`);
const editRes = await androidpublisher.edits.insert({ packageName, requestBody: {} });
const editId = editRes.data.id;
try {
  // List bundles uploaded
  const bundles = await androidpublisher.edits.bundles.list({ packageName, editId });
  const versions = (bundles.data.bundles ?? []).map((b) => b.versionCode);
  console.log(`[inspect] uploaded versionCodes: ${versions.join(', ') || '(none)'}`);

  for (const track of tracks) {
    try {
      const r = await androidpublisher.edits.tracks.get({ packageName, editId, track });
      const releases = r.data.releases ?? [];
      if (releases.length === 0) {
        console.log(`\n--- ${track}: (no releases)`);
        continue;
      }
      console.log(`\n--- ${track}:`);
      for (const rel of releases) {
        console.log(`  name=${rel.name ?? '?'}  status=${rel.status}  versionCodes=[${(rel.versionCodes ?? []).join(',')}]`);
        if (rel.userFraction != null) console.log(`    userFraction=${rel.userFraction}`);
        if (rel.inAppUpdatePriority != null) console.log(`    inAppUpdatePriority=${rel.inAppUpdatePriority}`);
        const notes = rel.releaseNotes ?? [];
        for (const n of notes) {
          const txt = (n.text ?? '').replace(/\n/g, ' / ');
          console.log(`    notes[${n.language}]: ${txt.slice(0, 120)}${txt.length > 120 ? '…' : ''}`);
        }
      }
    } catch (err) {
      console.log(`\n--- ${track}: ERROR ${err.message}`);
    }
  }
} finally {
  // Always discard the edit (read-only) so no orphaned drafts.
  try { await androidpublisher.edits.delete({ packageName, editId }); } catch {}
}

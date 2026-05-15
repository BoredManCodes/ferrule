#!/usr/bin/env node
// Drive the Play Console UI to promote a draft internal-testing release to
// "Available to internal testers". Used because the Publishing API rejects
// status='completed' while the app is still considered "Draft" by Google
// (i.e. before the App content checklist is fully completed and a production
// release exists).
//
// Auth: persistent Chromium profile in `scripts/.chromium-profile/`.
// First run: pass `--login`, sign in interactively, the cookies persist.
// Subsequent runs: drives the UI in a quick visible-browser pop-up.
//
// Usage:
//   node promote-via-browser.mjs --login            # one-time interactive sign-in
//   node promote-via-browser.mjs --release-name 1.0.1 [--version-code 2]
//                              [--track internal-testing]
//                              [--dev-account-id <id>]
//                              [--app-id <id>]
//                              [--headless] [--headed]
//
// Find dev-account-id / app-id from the URL while signed in to the Play
// Console:
//   https://play.google.com/console/u/0/developers/<DEV_ID>/app/<APP_ID>/tracks/internal-testing
//
// Override per-invocation via --dev-account-id / --app-id, or set
// PLAY_DEV_ACCOUNT_ID / PLAY_APP_ID env vars. Defaults below match the
// TPW developer account (same Google login); update PLAY_APP_ID for Ferrule.

import { existsSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROFILE_DIR = resolve(__dirname, '.chromium-profile');

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

const args = parseArgs(process.argv.slice(2));
const devId = String(
  args['dev-account-id'] ||
    process.env.PLAY_DEV_ACCOUNT_ID ||
    '4679601468196856322',
);
const appId = String(
  args['app-id'] || process.env.PLAY_APP_ID || 'REPLACE_WITH_FERRULE_APP_ID',
);
const track = String(args.track || 'internal-testing');
const releaseName = args['release-name'] ? String(args['release-name']) : null;
const versionCode = args['version-code'] ? String(args['version-code']) : null;
const loginMode = !!args.login;
const headless = !loginMode && !!args.headless && !args.headed;

if (!loginMode && appId === 'REPLACE_WITH_FERRULE_APP_ID') {
  console.error(
    '[promote] PLAY_APP_ID not set. Pass --app-id <id>, or set the env var.',
  );
  console.error(
    '[promote] Find it in the Play Console URL: .../developers/<dev>/app/<APP_ID>/tracks/...',
  );
  process.exit(2);
}

const trackUrl = `https://play.google.com/console/u/0/developers/${devId}/app/${appId}/tracks/${track}`;

if (!existsSync(PROFILE_DIR)) {
  mkdirSync(PROFILE_DIR, { recursive: true });
}

console.log(`[promote] profile=${PROFILE_DIR}`);
console.log(`[promote] track URL=${trackUrl}`);

await main();

async function main() {
  const context = await chromium.launchPersistentContext(PROFILE_DIR, {
    headless,
    viewport: { width: 1400, height: 900 },
  });

  try {
  const page = context.pages()[0] ?? (await context.newPage());

  if (loginMode) {
    console.log('');
    console.log('======================================================');
    console.log('  LOGIN MODE');
    console.log('  A NEW Chromium window has opened (controlled by Playwright).');
    console.log('  THAT is the window to sign in to -- not your normal Chrome.');
    console.log('  Sign in to Google with the Play Console owner account.');
    console.log('  This script will detect arrival on the dev console and');
    console.log('  close the window itself. Do NOT close the window manually.');
    console.log('======================================================');
    console.log('');
    try {
      await page.goto('https://play.google.com/console', {
        waitUntil: 'domcontentloaded',
      });
    } catch (e) {
      console.error('[promote] initial goto failed:', e.message);
      return;
    }
    console.log(`[promote] initial URL: ${page.url()}`);

    const targetMatched = (url) =>
      /play\.google\.com\/console\/.*\/developers\//.test(url);

    if (targetMatched(page.url())) {
      console.log('[promote] already at console, saving cookies...');
    } else {
      try {
        await new Promise((resolveP, rejectP) => {
          const timer = setTimeout(
            () => rejectP(new Error('timeout (10 min)')),
            10 * 60 * 1000,
          );

          page.on('framenavigated', (frame) => {
            if (frame !== page.mainFrame()) return;
            const url = frame.url();
            console.log(`[promote] nav -> ${url}`);
            if (targetMatched(url)) {
              clearTimeout(timer);
              resolveP();
            }
          });

          page.on('close', () => {
            clearTimeout(timer);
            rejectP(new Error('window closed'));
          });

          (async () => {
            while (true) {
              await new Promise((r) => setTimeout(r, 3000));
              if (page.isClosed()) return;
              const u = page.url();
              if (targetMatched(u)) {
                clearTimeout(timer);
                resolveP();
                return;
              }
            }
          })();
        });
      } catch (e) {
        console.error(`[promote] sign-in wait ended: ${e.message}`);
        return;
      }
    }

    await page.waitForTimeout(2500);
    try {
      await context.storageState({
        path: resolve(__dirname, '.chromium-profile', 'storage-state.json'),
      });
    } catch {}
    console.log(`[promote] sign-in detected at ${page.url()}`);
    console.log('[promote] cookies saved to profile.');
    return;
  }

  if (!releaseName && !versionCode) {
    throw new Error('Pass --release-name "1.0.X" or --version-code X');
  }
  const targetReleaseName = releaseName || versionCode;

  const screenshotOnFail = async (label) => {
    try {
      const file = resolve(__dirname, `.promote-fail-${label}-${Date.now()}.png`);
      await page.screenshot({ path: file, fullPage: true });
      console.error(`[promote] saved screenshot to ${file}`);
    } catch {}
  };

  await page.goto(trackUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  console.log(`[promote] landed on ${page.url()}`);

  if (!page.url().includes('/console/')) {
    throw new Error(
      `Not signed in (got ${page.url()}). Run: node promote-via-browser.mjs --login`,
    );
  }

  console.log(`[promote] looking for a draft release ("Edit release" button)...`);

  const editButton = page
    .getByRole('button', { name: 'Edit release', exact: true })
    .first();

  try {
    await editButton.waitFor({ timeout: 90000 });
  } catch (e) {
    await screenshotOnFail('edit-button');
    const liveText = page.getByText('Available to internal testers');
    if ((await liveText.count()) > 0) {
      const html = await page.content();
      if (html.includes(targetReleaseName)) {
        console.log(
          `[promote] ${targetReleaseName} appears to already be live (no Edit release button).`,
        );
        return;
      }
    }
    throw new Error(
      `No "Edit release" button found within 90s. The draft may not have been uploaded yet, or the page didn't load. ${e.message}`,
    );
  }

  await editButton.click();
  console.log('[promote] clicked Edit release');

  await page.waitForURL(/\/releases\/\d+\/prepare/, { timeout: 30000 });
  const nextBtn = page.getByRole('button', { name: 'Next', exact: true });
  await nextBtn.waitFor({ timeout: 30000 });
  await nextBtn.click();
  console.log('[promote] clicked Next');

  await page.waitForURL(/\/releases\/\d+\/review/, { timeout: 30000 });

  const saveBtn = page
    .getByRole('button', { name: 'Save and publish', exact: true })
    .first();
  await saveBtn.waitFor({ timeout: 30000 });
  await saveBtn.click();
  console.log('[promote] clicked Save and publish');

  const confirmBtn = page
    .getByRole('dialog')
    .getByRole('button', { name: 'Save and publish', exact: true });
  await confirmBtn.waitFor({ timeout: 30000 });
  await confirmBtn.click();
  console.log('[promote] confirmed dialog, waiting for publish...');

  await page.waitForURL(/\/tracks\/[^?]+\?tab=releases/, { timeout: 60000 });
  await page.waitForSelector('text=Available to internal testers', {
    timeout: 60000,
  });
    console.log(`[promote] ${targetReleaseName} is now live to internal testers.`);
  } finally {
    await context.close();
  }
}

#!/usr/bin/env node
// Promote a draft release on a Closed Testing track. The Closed Testing flow
// differs from Internal Testing in two ways:
//   1. The review page's primary CTA is "Save" (not "Save and publish") and
//      saving commits the draft to "Publishing overview" — not yet live.
//   2. To actually make the build available to testers you must visit the
//      Publishing overview and click "Send 1 change for review" (Google
//      then reviews + publishes).
//
// Auth: persistent Chromium profile in `scripts/.chromium-profile/` — same
// profile promote-via-browser.mjs uses. Run that script's --login flow first
// if cookies aren't set yet.
//
// Usage:
//   node promote-closed-testing.mjs --track <track-slug> --release-name 1.0.2
//                                   [--version-code 4]
//                                   [--no-review]   # save draft only
//                                   [--dev-account-id <id>] [--app-id <id>]
//                                   [--headed] [--headless]

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
const devId = String(args['dev-account-id'] || '4679601468196856322');
const appId = String(args['app-id'] || '4972026260377304123');
const track = String(args.track || '');
const releaseName = args['release-name'] ? String(args['release-name']) : null;
const versionCode = args['version-code'] ? String(args['version-code']) : null;
const skipReview = !!args['no-review'];
const headless = !!args.headless && !args.headed;

if (!track) {
  console.error('Missing --track <slug>. Example: --track 4698797810447037521');
  process.exit(2);
}

const trackUrl = `https://play.google.com/console/u/0/developers/${devId}/app/${appId}/tracks/${track}`;
const publishingOverviewUrl = `https://play.google.com/console/u/0/developers/${devId}/app/${appId}/publishing`;

if (!existsSync(PROFILE_DIR)) mkdirSync(PROFILE_DIR, { recursive: true });

console.log(`[promote-closed] profile=${PROFILE_DIR}`);
console.log(`[promote-closed] track URL=${trackUrl}`);
if (releaseName) console.log(`[promote-closed] expecting release "${releaseName}"`);
if (versionCode) console.log(`[promote-closed] expecting versionCode ${versionCode}`);

const ctx = await chromium.launchPersistentContext(PROFILE_DIR, {
  headless,
  viewport: { width: 1500, height: 950 },
});

try {
  await main();
} finally {
  await ctx.close();
}

async function main() {
  const page = ctx.pages()[0] ?? (await ctx.newPage());

  // Play pops a "help us improve" survey iframe that sits over the buttons
  // and eats clicks. Remove it whenever it shows up.
  await page.addLocatorHandler(page.locator('#google-hats-survey'), async () => {
    await page.evaluate(() => document.getElementById('google-hats-survey')?.remove());
  }, { noWaitAfter: true });

  const snap = async (name) => {
    try {
      const path = resolve(__dirname, `.promote-closed-${name}.png`);
      await page.screenshot({ path, fullPage: true });
      console.log(`[promote-closed] screenshot -> ${path}`);
    } catch {}
  };

  // 1) Land on the track page.
  await page.goto(trackUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  console.log(`[promote-closed] landed on ${page.url()}`);
  if (!page.url().includes('/console/')) {
    throw new Error(`Not signed in (got ${page.url()}).`);
  }

  // 2) Find "Edit release" (a draft already exists).
  const editBtn = page.getByRole('button', { name: 'Edit release', exact: true }).first();
  try {
    await editBtn.waitFor({ timeout: 60000 });
  } catch (e) {
    await snap('no-edit-button');
    throw new Error(`No "Edit release" button on track page within 60s — is there a draft? ${e.message}`);
  }
  await editBtn.click();
  await page.waitForURL(/\/releases\/\d+\/prepare/, { timeout: 30000 });
  console.log('[promote-closed] on prepare page');

  // 3) Click Next to advance to /review.
  const nextBtn = page.getByRole('button', { name: 'Next', exact: true });
  await nextBtn.waitFor({ timeout: 30000 });
  await nextBtn.click();
  await page.waitForURL(/\/releases\/\d+\/review/, { timeout: 30000 });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  console.log('[promote-closed] on review page');
  await snap('01-review');

  // 4) Click "Save" — commits draft into Publishing overview.
  //    Use exact match on the visible label. There are several "Save" buttons
  //    in modal dialogs; we want the one in the page footer.
  const saveBtn = page.getByRole('button', { name: 'Save', exact: true }).first();
  await saveBtn.waitFor({ timeout: 30000 });
  await saveBtn.click();
  console.log('[promote-closed] clicked Save');

  // 5) Confirm any dialog. Some Save flows pop a "Send changes to review now?" dialog.
  try {
    const dialogSend = page
      .getByRole('dialog')
      .getByRole('button', { name: /^(Save|Send.*review|Submit)$/, exact: false });
    await dialogSend.waitFor({ timeout: 15000 });
    await dialogSend.click();
    console.log('[promote-closed] confirmed dialog');
  } catch {
    // No dialog appeared — that's fine, the Save committed without one.
    console.log('[promote-closed] no confirmation dialog appeared');
  }

  // Give the save a moment to settle.
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await snap('02-after-save');
  console.log(`[promote-closed] after Save URL=${page.url()}`);

  if (skipReview) {
    console.log('[promote-closed] --no-review set; stopping here. Draft saved to Publishing overview.');
    return;
  }

  // 6) Go to Publishing overview and click "Send N changes for review".
  console.log(`[promote-closed] -> Publishing overview: ${publishingOverviewUrl}`);
  await page.goto(publishingOverviewUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2000);
  await snap('03-publishing-overview');

  // Look for a "Send N change(s) for review" / "Send for review" button.
  // If a previous review is in progress, Play hides this and shows a
  // "Restart review" affordance instead — handled below.
  const sendBtn = page
    .getByRole('button', { name: /^\s*((Send|Submit)( \d+)? changes?( for review)?|Send for review|Restart review)\s*$/i })
    .first();
  try {
    await sendBtn.waitFor({ timeout: 30000 });
  } catch (e) {
    await snap('no-send-button');
    throw new Error(`Could not find "Send for review" button on Publishing overview: ${e.message}`);
  }
  await sendBtn.click();
  console.log('[promote-closed] clicked Send for review');

  // Confirm any dialog. If a review is already in progress, the dialog asks
  // "Do you want to restart your review?" with a "Restart review" button.
  try {
    const confirm = page
      .getByRole('dialog')
      .getByRole('button', { name: /Send.*review|Restart.*review|Submit|Confirm|OK/i })
      .first();
    await confirm.waitFor({ timeout: 15000 });
    await confirm.click();
    console.log('[promote-closed] confirmed Send/Restart-review dialog');
  } catch {
    console.log('[promote-closed] no Send/Restart-review confirmation dialog appeared');
  }

  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await snap('04-sent-for-review');
  console.log('[promote-closed] sent for Google review.');
}

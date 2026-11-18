#!/usr/bin/env node
// Navigates to Publishing overview and clicks "Send N change(s) for review"
// (or "Restart review" if an existing review is in progress). Use when a
// draft is already saved into Publishing overview but not yet sent.
//
// Usage:
//   node send-for-review.mjs [--dev-account-id <id>] [--app-id <id>]
//                            [--headed] [--headless]

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
const headless = !!args.headless && !args.headed;
const publishingUrl = `https://play.google.com/console/u/0/developers/${devId}/app/${appId}/publishing`;

if (!existsSync(PROFILE_DIR)) mkdirSync(PROFILE_DIR, { recursive: true });

console.log(`[send-for-review] -> ${publishingUrl}`);

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
      const path = resolve(__dirname, `.send-for-review-${name}.png`);
      await page.screenshot({ path, fullPage: true });
      console.log(`[send-for-review] screenshot -> ${path}`);
    } catch {}
  };

  await page.goto(publishingUrl, { waitUntil: 'domcontentloaded' });
  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(2000);
  console.log(`[send-for-review] landed on ${page.url()}`);
  await snap('01-publishing-overview');

  const sendBtn = page
    .getByRole('button', { name: /^\s*((Send|Submit)( \d+)? changes?( for review)?|Send for review)\s*$/i })
    .first();
  try {
    await sendBtn.waitFor({ timeout: 30000 });
  } catch (e) {
    await snap('no-send-button');
    throw new Error(`No "Send for review" button visible on Publishing overview: ${e.message}`);
  }
  await sendBtn.click();
  console.log('[send-for-review] clicked Send for review');

  // The dialog when a review is already in progress says "Restart review".
  try {
    const confirm = page
      .getByRole('dialog')
      .getByRole('button', { name: /Send.*review|Restart.*review|Submit|Confirm|OK/i })
      .first();
    await confirm.waitFor({ timeout: 15000 });
    const label = await confirm.innerText().catch(() => '');
    await confirm.click();
    console.log(`[send-for-review] confirmed dialog (clicked "${label.trim()}")`);
  } catch {
    console.log('[send-for-review] no confirmation dialog appeared');
  }

  await page.waitForLoadState('networkidle', { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);
  await snap('02-after-send');
  console.log(`[send-for-review] final URL=${page.url()}`);
}

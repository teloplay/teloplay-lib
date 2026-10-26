// Playwright standalone test runner
import { test } from '@playwright/test';

test.use({ baseURL: 'http://localhost:8089' });

test('capture screenshots', async ({ page }) => {
  // Desktop
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.goto('/');
  await page.waitForTimeout(1000);
  await page.screenshot({ path: 'docs/screenshots/landing-desktop-1440.png', fullPage: true });

  // Tablet
  await page.setViewportSize({ width: 1024, height: 768 });
  await page.goto('/');
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'docs/screenshots/landing-tablet-1024.png', fullPage: true });

  // Mobile
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto('/');
  await page.waitForTimeout(500);
  await page.screenshot({ path: 'docs/screenshots/landing-mobile-375.png', fullPage: true });
});

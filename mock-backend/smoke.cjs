// Run inside MDR with Playwright and Chromium installed. Uses real Keycloak SAML login.
const assert = require('node:assert/strict');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || '/opt/node_modules/@playwright/test');

(async () => {
  const base = process.env.SAML_DJANGO_BASE_URL;
  assert(base, 'Set SAML_DJANGO_BASE_URL to the current MDR URL');
  const browser = await chromium.launch({args: ['--no-sandbox', '--host-resolver-rules=MAP *.dh.unimaas.nl 172.21.1.100']});
  try {
    for (const user of ['dlinssen', 'minimalist']) {
      const context = await browser.newContext({ignoreHTTPSErrors: true});
      const page = await context.newPage();
      const serverErrors = [];
      page.on('response', response => {
        if (response.status() >= 500) serverErrors.push(`${response.status()} ${response.url()}`);
      });
      await page.goto(base, {waitUntil: 'domcontentloaded'});
      await page.locator('#username').fill(user);
      await page.locator('#password').fill(process.env.DEMO_KEYCLOAK_PASSWORD || 'foobar');
      await Promise.all([
        page.waitForURL(url => url.origin === new URL(base).origin && url.pathname === '/', {timeout: 30000}),
        page.locator('#kc-login').click(),
      ]);
      const home = await page.locator('body').innerText();
      assert(home.includes('Shared microscopy study'), `${user}: shared project missing`);
      assert.equal(home.includes('Administrator research project'), user === 'dlinssen');
      for (const path of ['/projects/P000000001', '/projects/P000000001/C000000001/',
                          '/hdl/P000000001/C000000001/', '/projects/P000000001/C000000001/edit',
                          '/processes/index', '/dropzone/upload/mock-direct',
                          '/dropzone/edit/mounted/mock-mounted', '/credentials']) {
        const response = await page.goto(base + path, {waitUntil: 'domcontentloaded'});
        assert.equal(response.status(), 200, `${user}: ${path}`);
      }
      assert.deepEqual(serverErrors, [], `${user}: browser saw server errors`);
      await page.screenshot({path: `/tmp/mdr-mock-${user}.png`, fullPage: true});
      console.log(`${user}: Keycloak login, project visibility, browsing, metadata, dropzones and credentials passed`);
      await context.close();
    }
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });

const puppeteer = require('/tmp/test-puppeteer/node_modules/puppeteer');
const path = require('path');
const fs = require('fs');

const BROWSER_PATH = '/tmp/test-puppeteer/chrome-headless-shell/linux_arm-159.0.8138.0/chrome-headless-shell-linux-arm64/chrome-headless-shell';
const HTML_FILE = 'file://' + path.resolve(__dirname, 'ui_preview.html');
const SCREENSHOTS_DIR = path.resolve(__dirname, 'screenshots');

async function run() {
  if (!fs.existsSync(SCREENSHOTS_DIR)) {
    fs.mkdirSync(SCREENSHOTS_DIR, { recursive: true });
  }

  console.log('Launching browser at:', BROWSER_PATH);
  const browser = await puppeteer.launch({
    executablePath: BROWSER_PATH,
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox']
  });

  const page = await browser.newPage();
  await page.setViewport({ width: 2000, height: 950, deviceScaleFactor: 1 });
  await page.goto(HTML_FILE, { waitUntil: 'networkidle0' });

  // 1. Full Mac Workbench Preview
  console.log('Rendering 1: Mac Workbench Preview...');
  await page.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'mac_workbench_preview.png'),
    fullPage: false
  });

  // 2. Exact 1920x720 Head Unit Canvas (Native Widescreen)
  console.log('Rendering 2: Exact 1920x720 Head Unit Canvas...');
  const screenEl = await page.$('#headunit-screen');
  await screenEl.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'headunit_1920x720.png')
  });

  // 3. Exact 1280x720 Viewport Mode
  console.log('Rendering 3: Exact 1280x720 Mode...');
  await page.evaluate(() => setViewport('1280'));
  await new Promise(r => setTimeout(r, 400));
  const wrapper1280 = await page.$('#viewport-wrapper');
  await wrapper1280.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'headunit_1280x720.png')
  });

  // Reset to 1920
  await page.evaluate(() => setViewport('1920'));
  await new Promise(r => setTimeout(r, 400));

  // 4. Warning Opt-in Dialog (dialog_alert.xml)
  console.log('Rendering 4: Warning Opt-in Dialog...');
  await page.evaluate(() => toggleWarningDialog(true));
  await new Promise(r => setTimeout(r, 300));
  await screenEl.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'headunit_warning_dialog.png')
  });
  await page.evaluate(() => toggleWarningDialog(false));

  // 5. Assign Phone Modal
  console.log('Rendering 5: Assign Phone Dialog...');
  await page.evaluate(() => openAssignModal(1));
  await new Promise(r => setTimeout(r, 300));
  await screenEl.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'headunit_assign_modal.png')
  });
  await page.evaluate(() => closeAssignModal());

  // 6. Active Toast Notification Banner
  console.log('Rendering 6: Toast Notification Banner...');
  await page.evaluate(() => showToast('Profile switched to Driver 1 (Pixel 11 Pro XL detected via Bluetooth + Wi-Fi)'));
  await new Promise(r => setTimeout(r, 450));
  await screenEl.screenshot({
    path: path.join(SCREENSHOTS_DIR, 'headunit_toast_banner.png')
  });

  await browser.close();
  console.log('All screenshots rendered successfully in:', SCREENSHOTS_DIR);
}

run().catch(err => {
  console.error('Render failed:', err);
  process.exit(1);
});

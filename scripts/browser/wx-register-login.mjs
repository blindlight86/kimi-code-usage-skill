#!/usr/bin/env node
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

async function loadPuppeteer() {
  const customPath = process.env.KIMI_PUPPETEER_ESM;
  const localPuppeteerEsm = path.resolve(
    __dirname,
    "..",
    "..",
    "node_modules",
    "puppeteer",
    "lib",
    "esm",
    "puppeteer",
    "puppeteer.js"
  );
  const homePuppeteerEsm = path.join(
    os.homedir(),
    ".agents",
    "skills",
    "chrome-devtools",
    "scripts",
    "node_modules",
    "puppeteer",
    "lib",
    "esm",
    "puppeteer",
    "puppeteer.js"
  );

  const candidates = [
    customPath || "",
    localPuppeteerEsm,
    homePuppeteerEsm,
  ].filter(Boolean);

  for (const p of candidates) {
    if (fs.existsSync(p)) {
      const mod = await import(`file://${p}`);
      return mod.default || mod;
    }
  }

  try {
    const mod = await import("puppeteer");
    return mod.default || mod;
  } catch {
    throw new Error(
      "Cannot load puppeteer. Set KIMI_PUPPETEER_ESM or install puppeteer in this skill workspace."
    );
  }
}

function redact(s) {
  if (!s) return "";
  if (s.length <= 10) return "***";
  return `****...${s.slice(-4)}`;
}

async function clickByText(page, candidates) {
  return page.evaluate((texts) => {
    const nodes = Array.from(
      document.querySelectorAll("button, a, [role='button'], div, span")
    );
    for (const n of nodes) {
      const text = (n.textContent || "").trim().toLowerCase();
      if (!text) continue;
      if (texts.some((t) => text.includes(String(t).toLowerCase()))) {
        if (n instanceof HTMLElement) {
          n.click();
          return true;
        }
      }
    }
    return false;
  }, candidates);
}

async function clickLoginButton(page) {
  return page.evaluate(() => {
    const isVisible = (el) => {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      return (
        rect.width > 0 &&
        rect.height > 0 &&
        style.visibility !== "hidden" &&
        style.display !== "none"
      );
    };
    const norm = (s) => s.replace(/\s+/g, " ").trim().toLowerCase();
    const nodes = Array.from(document.querySelectorAll("button, a, [role='button'], div, span"));
    const target = nodes.find((n) => {
      const txt = norm(n.textContent || "");
      return isVisible(n) && (txt === "log in" || txt === "登录");
    });
    if (target && target instanceof HTMLElement) {
      target.click();
      return true;
    }
    return false;
  });
}

async function main() {
  const args = process.argv.slice(2);
  const timeoutSec = Number(process.env.KIMI_QR_LOGIN_TIMEOUT_SEC || 180);
  const screenshotPath =
    process.env.KIMI_QR_SCREENSHOT ||
    path.join(process.cwd(), "docs", "screenshots", "kimi-login-qr.png");
  const headless = !args.includes("--show-browser");

  const puppeteer = await loadPuppeteer();
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), "kimi-clean-profile-"));

  const browser = await puppeteer.launch({
    executablePath:
      process.env.KIMI_CHROME_PATH ||
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    headless,
    userDataDir: profile,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
    defaultViewport: { width: 1280, height: 900 },
  });

  try {
    const page = await browser.newPage();
    let loginId = "";

    page.on("response", async (res) => {
      try {
        const url = res.url();
        if (!url.includes("/api/user/wx/register_login")) return;
        const text = await res.text();
        const data = JSON.parse(text);
        if (!loginId && typeof data.id === "string" && data.id) {
          loginId = data.id;
        }
      } catch {
        // Ignore non-JSON responses.
      }
    });

    await page.goto("https://www.kimi.com/code/en", {
      waitUntil: "domcontentloaded",
      timeout: 60000,
    });
    await new Promise((r) => setTimeout(r, 3000));

    // Ensure login flow is opened before screenshot.
    await clickLoginButton(page);
    await new Promise((r) => setTimeout(r, 3500));

    // Wait until login id is captured from register_login request.
    const loginWaitDeadline = Date.now() + 12000;
    while (!loginId && Date.now() < loginWaitDeadline) {
      await new Promise((r) => setTimeout(r, 300));
    }

    // Wait briefly for QR-related UI nodes.
    try {
      await page.waitForFunction(
        () => {
          const qrSelectors = [
            "canvas",
            "img[src*='qr']",
            "img[alt*='QR']",
            "[class*='qr']",
            "[class*='qrcode']",
          ];
          return qrSelectors.some((s) => document.querySelector(s));
        },
        { timeout: 8000 }
      );
    } catch {
      // continue with full-page screenshot fallback
    }

    fs.mkdirSync(path.dirname(screenshotPath), { recursive: true });
    // Prefer QR area screenshot when possible, fallback to viewport screenshot.
    const qrElement =
      (await page.$("img[src*='qr']")) ||
      (await page.$("img[alt*='QR']")) ||
      (await page.$("[class*='qrcode'] canvas")) ||
      (await page.$("[class*='qr'] canvas")) ||
      (await page.$("canvas"));
    if (qrElement) {
      await qrElement.screenshot({ path: screenshotPath });
    } else {
      await page.screenshot({ path: screenshotPath, fullPage: false });
    }

    // Signal test/fallback mode without requiring real scan.
    if (process.env.KIMI_BOOTSTRAP_MARKER) {
      fs.writeFileSync(process.env.KIMI_BOOTSTRAP_MARKER, "ok\n");
    }

    if (!loginId) {
      // Fallback: directly create login session id from page context.
      loginId = await page.evaluate(async () => {
        const r = await fetch("/api/user/wx/register_login", {
          method: "POST",
          headers: {
            accept: "application/json, text/plain, */*",
            "content-type": "application/json",
            "x-language": "zh-CN",
            "x-msh-platform": "web",
          },
          body: "{}",
        });
        const data = await r.json();
        return typeof data?.id === "string" ? data.id : "";
      });
    }

    if (loginId) {
      console.log(
        JSON.stringify(
          {
            success: true,
            login_id: loginId,
            qr_screenshot: screenshotPath,
            qr_expires_in_seconds: timeoutSec,
            message_for_session: `请在 ${timeoutSec} 秒内扫码登录。`,
          },
          null,
          2
        )
      );
      return;
    }

    console.log(
      JSON.stringify(
        {
          success: false,
          reason: "failed to capture login id",
          login_id: loginId,
          qr_screenshot: screenshotPath,
        },
        null,
        2
      )
    );
    process.exitCode = 1;
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(
    JSON.stringify(
      {
        success: false,
        error: err.message,
      },
      null,
      2
    )
  );
  process.exit(1);
});

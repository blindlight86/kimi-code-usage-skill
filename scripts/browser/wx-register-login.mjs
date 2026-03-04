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

async function main() {
  const args = process.argv.slice(2);
  const timeoutSec = Number(process.env.KIMI_QR_LOGIN_TIMEOUT_SEC || 180);
  const screenshotPath =
    process.env.KIMI_QR_SCREENSHOT ||
    path.join(process.cwd(), "docs", "screenshots", "kimi-login-qr.png");
  const headless = args.includes("--headless");

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
    let captured = { access_token: "", refresh_token: "" };

    page.on("response", async (res) => {
      try {
        const url = res.url();
        if (!url.includes("/api/user/wx/register_login")) return;
        const text = await res.text();
        const data = JSON.parse(text);
        if (!loginId && typeof data.id === "string" && data.id) {
          loginId = data.id;
        }
        if (data.access_token && data.refresh_token) {
          captured = {
            access_token: data.access_token,
            refresh_token: data.refresh_token,
          };
        }
      } catch {
        // Ignore non-JSON responses.
      }
    });

    await page.goto("https://www.kimi.com/code/en", {
      waitUntil: "domcontentloaded",
      timeout: 60000,
    });
    await new Promise((r) => setTimeout(r, 5000));

    fs.mkdirSync(path.dirname(screenshotPath), { recursive: true });
    await page.screenshot({ path: screenshotPath, fullPage: false });

    // Signal test/fallback mode without requiring real scan.
    if (process.env.KIMI_BOOTSTRAP_MARKER) {
      fs.writeFileSync(process.env.KIMI_BOOTSTRAP_MARKER, "ok\n");
    }

    const deadline = Date.now() + timeoutSec * 1000;
    while (Date.now() < deadline) {
      if (captured.access_token && captured.refresh_token) break;
      await new Promise((r) => setTimeout(r, 1000));
    }

    if (captured.access_token && captured.refresh_token) {
      console.log(
        JSON.stringify(
          {
            success: true,
            login_id: loginId,
            qr_screenshot: screenshotPath,
            access_token: captured.access_token,
            refresh_token: captured.refresh_token,
            access_token_redacted: redact(captured.access_token),
            refresh_token_redacted: redact(captured.refresh_token),
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
          reason: "timeout waiting for QR scan",
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

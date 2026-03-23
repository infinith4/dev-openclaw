"""Playwright browser session management for NotebookLM."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import TYPE_CHECKING

from playwright.sync_api import sync_playwright

if TYPE_CHECKING:
    from playwright.sync_api import Browser, BrowserContext, Page, Playwright

logger = logging.getLogger(__name__)

NOTEBOOKLM_URL = "https://notebooklm.google.com/"

# Default directory for persisted browser profile (Google login state).
DEFAULT_PROFILE_DIR = Path.home() / ".notebooklm-profile"


class BrowserSession:
    """Manage a Chromium browser session with a persistent profile.

    The persistent profile lets users log in to Google once and reuse the
    session across runs without re-authenticating.
    """

    def __init__(
        self,
        profile_dir: Path | None = None,
        headless: bool = False,
        slow_mo: int = 0,
    ) -> None:
        self.profile_dir = profile_dir or DEFAULT_PROFILE_DIR
        self.headless = headless
        self.slow_mo = slow_mo

        self._pw: Playwright | None = None
        self._browser: Browser | None = None
        self._context: BrowserContext | None = None
        self._page: Page | None = None

    # -- lifecycle -----------------------------------------------------------

    def start(self) -> Page:
        """Launch the browser and return a ready page."""
        self.profile_dir.mkdir(parents=True, exist_ok=True)

        self._pw = sync_playwright().start()
        self._context = self._pw.chromium.launch_persistent_context(
            user_data_dir=str(self.profile_dir),
            headless=self.headless,
            slow_mo=self.slow_mo,
            accept_downloads=True,
            locale="ja-JP",
            args=["--disable-blink-features=AutomationControlled"],
        )
        self._page = self._context.new_page()
        logger.info("Browser started (profile=%s)", self.profile_dir)
        return self._page

    def close(self) -> None:
        """Shut down context, browser, and Playwright."""
        if self._context:
            self._context.close()
        if self._pw:
            self._pw.stop()
        logger.info("Browser closed")

    # -- helpers -------------------------------------------------------------

    @property
    def page(self) -> Page:
        if self._page is None:
            raise RuntimeError("Browser not started. Call start() first.")
        return self._page

    def navigate_to_notebooklm(self) -> None:
        """Open the NotebookLM top page and wait for it to load."""
        self.page.goto(NOTEBOOKLM_URL, wait_until="networkidle")
        logger.info("Navigated to %s", NOTEBOOKLM_URL)

    # -- context manager -----------------------------------------------------

    def __enter__(self) -> "BrowserSession":
        self.start()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

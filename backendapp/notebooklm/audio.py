"""Generate and download Audio Overview from NotebookLM."""

from __future__ import annotations

import logging
import shutil
from pathlib import Path

from playwright.sync_api import Download, Page

logger = logging.getLogger(__name__)

# How long to wait for audio generation (ms).  NotebookLM can take several
# minutes to generate an Audio Overview depending on source length.
GENERATION_TIMEOUT_MS = 600_000  # 10 min


def open_audio_panel(page: Page) -> None:
    """Open the Audio Overview panel inside the current notebook."""
    audio_btn = page.locator(
        "button:has-text('Audio Overview'), "
        "button:has-text('音声の概要'), "
        "[aria-label='Audio Overview'], "
        "[aria-label='音声の概要']"
    )
    audio_btn.first.click(timeout=15_000)
    page.wait_for_timeout(2_000)
    logger.info("Audio Overview panel opened")


def generate_audio(page: Page) -> None:
    """Click 'Generate' and wait for the audio to be ready."""
    gen_btn = page.locator(
        "button:has-text('Generate'), "
        "button:has-text('生成'), "
        "button:has-text('生成する')"
    )
    gen_btn.first.click(timeout=15_000)
    logger.info(
        "Audio generation started – waiting up to %d s …", GENERATION_TIMEOUT_MS // 1000
    )

    # Wait for a play button or download link to appear, indicating completion.
    done_indicator = page.locator(
        "button:has-text('Play'), "
        "button:has-text('再生'), "
        "[aria-label='Play'], "
        "[aria-label='再生'], "
        "button:has-text('Download'), "
        "button:has-text('ダウンロード'), "
        "a[download]"
    )
    done_indicator.first.wait_for(state="visible", timeout=GENERATION_TIMEOUT_MS)
    logger.info("Audio generation completed")


def download_audio(page: Page, output_dir: Path) -> Path:
    """Download the generated audio file and return its local path."""
    output_dir.mkdir(parents=True, exist_ok=True)

    dl_btn = page.locator(
        "button:has-text('Download'), "
        "button:has-text('ダウンロード'), "
        "[aria-label='Download audio'], "
        "[aria-label='音声をダウンロード'], "
        "a[download]"
    )

    # Use the three-dot / overflow menu if there is no direct download button.
    if dl_btn.count() == 0:
        overflow = page.locator(
            "button:has-text('More'), "
            "button[aria-label='More options'], "
            "button[aria-label='その他のオプション']"
        )
        if overflow.count() > 0:
            overflow.first.click(timeout=5_000)
            page.wait_for_timeout(1_000)

    with page.expect_download(timeout=60_000) as dl_info:
        dl_btn.first.click(timeout=15_000)

    download: Download = dl_info.value
    suggested = download.suggested_filename or "audio_overview.wav"
    dest = output_dir / suggested

    # Save to the target directory.
    tmp_path = download.path()
    if tmp_path:
        shutil.move(str(tmp_path), str(dest))
    else:
        download.save_as(str(dest))

    logger.info("Audio saved to %s", dest)
    return dest

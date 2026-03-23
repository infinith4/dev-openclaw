"""Upload files (PDF / images) to a NotebookLM notebook."""

from __future__ import annotations

import logging
from pathlib import Path

from playwright.sync_api import Page

logger = logging.getLogger(__name__)

ALLOWED_EXTENSIONS = {".pdf", ".png", ".jpg", ".jpeg", ".gif", ".webp"}

# Timeout for the upload to finish processing (ms).
UPLOAD_TIMEOUT_MS = 120_000


def validate_files(paths: list[Path]) -> list[Path]:
    """Return validated absolute paths, raising on missing or unsupported files."""
    validated: list[Path] = []
    for p in paths:
        resolved = p.resolve()
        if not resolved.is_file():
            raise FileNotFoundError(f"File not found: {resolved}")
        if resolved.suffix.lower() not in ALLOWED_EXTENSIONS:
            raise ValueError(
                f"Unsupported file type: {resolved.suffix} "
                f"(allowed: {', '.join(sorted(ALLOWED_EXTENSIONS))})"
            )
        validated.append(resolved)
    return validated


def create_notebook(page: Page, name: str) -> None:
    """Click the 'New notebook' button and optionally rename it."""
    # NotebookLM landing page has a "New notebook" / "新しいノートブック" button.
    new_btn = page.locator(
        "button:has-text('New notebook'), "
        "button:has-text('新しいノートブック'), "
        "button:has-text('Create new')"
    )
    new_btn.first.click(timeout=15_000)
    page.wait_for_load_state("networkidle")
    logger.info("Created new notebook")

    # Rename if the title field is visible.
    title_field = page.locator(
        "[aria-label='Notebook title'], "
        "[aria-label='ノートブックのタイトル'], "
        "input[data-notebook-title]"
    )
    if title_field.count() > 0:
        title_field.first.click()
        title_field.first.fill(name)
        page.keyboard.press("Enter")
        logger.info("Renamed notebook to %r", name)


def upload_sources(page: Page, files: list[Path]) -> None:
    """Upload source files to the currently-open notebook.

    NotebookLM exposes an 'Add source' button that opens a file-chooser
    dialog.  We intercept the filechooser event and set the files
    programmatically.
    """
    add_source_btn = page.locator(
        "button:has-text('Add source'), "
        "button:has-text('ソースを追加'), "
        "[aria-label='Add source'], "
        "[aria-label='ソースを追加']"
    )
    add_source_btn.first.click(timeout=15_000)

    # A menu may appear; click the "Upload" / "File upload" option.
    upload_option = page.locator(
        "text=File upload, text=ファイルをアップロード, text=Upload, text=アップロード"
    )
    if upload_option.count() > 0:
        upload_option.first.click(timeout=10_000)

    # Intercept the file chooser and set files.
    with page.expect_file_chooser(timeout=15_000) as fc_info:
        # Some UIs need a second click on "choose files" inside the dialog.
        choose_btn = page.locator(
            "button:has-text('Choose files'), "
            "button:has-text('ファイルを選択'), "
            "input[type='file']"
        )
        if choose_btn.count() > 0:
            choose_btn.first.click(timeout=10_000)

    file_chooser = fc_info.value
    file_chooser.set_files([str(f) for f in files])
    logger.info("Set %d file(s) in file chooser", len(files))

    # Wait for upload processing to complete.
    # NotebookLM shows a progress indicator; we wait until sources appear.
    page.wait_for_timeout(3_000)  # brief settle
    _wait_for_sources_ready(page, len(files))


def _wait_for_sources_ready(page: Page, expected_count: int) -> None:
    """Poll until the expected number of sources are listed."""
    # Look for source list items.
    source_items = page.locator("[data-source-id], .source-item, .source-card")

    try:
        source_items.nth(expected_count - 1).wait_for(
            state="visible", timeout=UPLOAD_TIMEOUT_MS
        )
        logger.info("All %d source(s) uploaded and ready", expected_count)
    except Exception:
        actual = source_items.count()
        logger.warning(
            "Expected %d sources but found %d after timeout",
            expected_count,
            actual,
        )

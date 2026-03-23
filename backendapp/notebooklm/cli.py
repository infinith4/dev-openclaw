"""CLI entry point for NotebookLM Audio Overview generator.

Usage::

    python -m backendapp.notebooklm --help
    python -m backendapp.notebooklm file1.pdf file2.png
    python -m backendapp.notebooklm --notebook "My Project" -o ./output file.pdf
"""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

from backendapp.notebooklm.audio import download_audio, generate_audio, open_audio_panel
from backendapp.notebooklm.browser import BrowserSession
from backendapp.notebooklm.uploader import (
    create_notebook,
    upload_sources,
    validate_files,
)

logger = logging.getLogger(__name__)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="notebooklm",
        description="Upload files to Google NotebookLM and generate an Audio Overview.",
    )
    parser.add_argument(
        "files",
        nargs="+",
        type=Path,
        help="PDF or image files to upload (PNG, JPG, GIF, WebP).",
    )
    parser.add_argument(
        "--notebook",
        default="Overnight Audio",
        help="Name for the new notebook (default: 'Overnight Audio').",
    )
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        default=Path("./output"),
        help="Directory to save the downloaded audio file (default: ./output).",
    )
    parser.add_argument(
        "--profile-dir",
        type=Path,
        default=None,
        help="Path to Chromium user-data dir with Google login session.",
    )
    parser.add_argument(
        "--headless",
        action="store_true",
        default=False,
        help="Run the browser in headless mode (may fail on Google login).",
    )
    parser.add_argument(
        "--slow-mo",
        type=int,
        default=300,
        help="Slow down Playwright actions by N ms (default: 300).",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        default=False,
        help="Enable verbose (DEBUG) logging.",
    )
    return parser


def run(args: argparse.Namespace) -> Path:
    """Execute the full workflow and return the downloaded audio path."""
    files = validate_files(args.files)
    logger.info("Validated %d file(s)", len(files))

    with BrowserSession(
        profile_dir=args.profile_dir,
        headless=args.headless,
        slow_mo=args.slow_mo,
    ) as session:
        session.navigate_to_notebooklm()
        create_notebook(session.page, args.notebook)
        upload_sources(session.page, files)
        open_audio_panel(session.page)
        generate_audio(session.page)
        audio_path = download_audio(session.page, args.output_dir)

    return audio_path


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    try:
        audio_path = run(args)
        print(f"Audio saved: {audio_path}")
    except FileNotFoundError as exc:
        logger.error("%s", exc)
        sys.exit(1)
    except ValueError as exc:
        logger.error("%s", exc)
        sys.exit(1)
    except KeyboardInterrupt:
        logger.info("Interrupted by user")
        sys.exit(130)
    except Exception as exc:
        logger.error("Unexpected error: %s", exc, exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

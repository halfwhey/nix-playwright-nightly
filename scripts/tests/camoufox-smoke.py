"""Verify the bundled browser and Python paths without downloading a browser."""

from pathlib import Path

from camoufox.pkgman import get_path, launch_path
from playwright.sync_api import sync_playwright

executable = launch_path()
assert Path(executable).is_file(), executable
assert Path(get_path("properties.json")).is_file()
with sync_playwright() as playwright:
    with playwright.firefox.launch(
        executable_path=executable, headless=True
    ) as browser:
        page = browser.new_page()
        page.set_content("<title>Camoufox smoke test</title><p>Apple Silicon</p>")
        assert page.title() == "Camoufox smoke test"
print(f"Camoufox launched successfully: {executable}")

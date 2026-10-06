# Ultrapool Together website

The website helps players install Together, invite friends, and learn its rules. The complete website source lives in `docs/`: short player guides in `content/`, templates in `templates/`, and images/fonts in `assets/`. Engineering notes remain as the other Markdown files beside this guide. Use those notes to check facts without copying their development history into the player guide.

## Build and preview

The website builder needs **Python 3.11 or newer**.

From the repository root:

```sh
python3 -m venv .local/site-venv
.local/site-venv/bin/python -m pip install -r docs/requirements.txt
.local/site-venv/bin/python docs/build.py --check
.local/site-venv/bin/python -m http.server 8000 --directory dist/site
```

On Windows, use `.local\site-venv\Scripts\python.exe` for the virtual environment commands. Open <http://localhost:8000>. The generated site lives in `dist/site/`, which is ignored by Git.

`--check` validates local links, anchors, images, stylesheets, headings, and template tokens. Review desktop and mobile layouts in a browser too.

## Publishing with GitHub Pages

The `pages.yml` workflow runs `python docs/build.py --check` on pull requests and publishes its `dist/site/` output when changes reach `main`. It builds from `docs/`; generated HTML is not committed. You can also run it manually from `main`.

GitHub Pages uses **GitHub Actions** as its publishing source. The workflow builds the files in `docs/` and deploys them to <https://harsh2204.github.io/ultrapool-together/>. For a new fork, enable that source under **Settings → Pages → Build and deployment**.

Publishing the site does not publish a new mod release. Keep the download link pointed at GitHub Releases, and label upcoming features clearly.

## Editing

- `templates/` holds the shared shell, homepage, documentation index, and gallery layout.
- `assets/site.css` and `assets/site.js` provide styling and interactions.
- `content/` holds every player article. Keep each focused on what someone needs to do or know while playing.
- `build.py` lists the articles. Link between guides with their Markdown filenames; the builder turns those links into website addresses.
- All generated pages sit at the site root and use relative asset links, so the site works under GitHub's repository subpath.
- `assets/gallery/provenance.json` records each screenshot’s source, date, caption, and hash. Keep screenshots unedited and retain their capture records. Making new captures requires permission to run the game; a website build never starts it.

Screenshots may show older versions. Don’t use them to promise that a feature is available in the latest download.

## Font credits

The site serves its fonts locally: **Barlow Condensed** by [the Barlow Project Authors](https://github.com/jpt/barlow) and **DM Sans** by [the DM Sans Project Authors](https://github.com/googlefonts/dm-fonts). Both use the SIL Open Font License 1.1. Their original copyright and license notices are retained beside the font files in `assets/fonts/barlow-OFL.txt` and `assets/fonts/dm-sans-OFL.txt` and copied into the published site.

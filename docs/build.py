#!/usr/bin/env python3
"""Build the project website from its templates and player guides."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from html import escape
from html.parser import HTMLParser
from hashlib import sha256
import json
from pathlib import Path
import re
import shutil
import sys
from urllib.parse import quote, unquote, urlsplit, urlunsplit

try:
    import markdown
    from markdown.extensions import Extension
    from markdown.treeprocessors import Treeprocessor
except ImportError:
    sys.exit("Install site dependencies first: python -m pip install -r docs/requirements.txt")


SITE = Path(__file__).resolve().parent
ROOT = SITE.parent
OUTPUT = ROOT / "dist" / "site"
REPOSITORY = "https://github.com/harsh2204/ultrapool-together"
CANONICAL = "https://harsh2204.github.io/ultrapool-together/"


@dataclass(frozen=True)
class Guide:
    slug: str
    source: str
    title: str
    description: str
    category: str


GUIDES = [
    Guide("get-started", "docs/content/get-started.md", "Get started", "Install Together and invite your friends.", "First game"),
    Guide("play", "docs/content/play.md", "Play together", "Choose a mode, take turns, and watch other tables.", "First game"),
    Guide("shared-shop", "docs/content/shared-shop.md", "Shopping together", "Share your money, arrange your build, and ready up.", "Playing"),
    Guide("custom-cues", "docs/content/custom-cues.md", "Cue Workshop", "Find a cue you like and pick a free finish.", "Playing"),
    Guide("multiplayer-balls", "docs/content/multiplayer-balls.md", "Multiplayer balls", "Eight optional balls with team bonuses and shared rewards.", "Playing"),
    Guide("expansion-sets", "docs/content/expansion-sets.md", "Expansion sets", "Six more sets to try in the shop.", "Playing"),
    Guide("save-import", "docs/content/save-import.md", "Saves and progress", "Copy Steam progress or find an earlier backup.", "Help"),
    Guide("compatibility", "docs/content/compatibility.md", "Versions and troubleshooting", "Help with updates, room codes, and joining friends.", "Help"),
]


def source_guides() -> list[Guide]:
    guides = list(GUIDES)
    if (SITE / "content/after-hours.md").is_file():
        guides.insert(6, Guide("after-hours", "docs/content/after-hours.md", "After the final shot", "Coming soon: compare every table’s final build.", "Playing"))
    return guides


class LocalLinks(Treeprocessor):
    def __init__(self, md, source: Path, registry: dict[Path, str]):
        super().__init__(md)
        self.source = source
        self.registry = registry

    def run(self, root):
        for element in root.iter():
            attribute = "href" if element.tag == "a" else "src" if element.tag == "img" else None
            if not attribute or not element.get(attribute):
                continue
            original = element.get(attribute)
            url = urlsplit(original)
            if url.scheme or url.netloc or not url.path:
                continue
            # Markdown links are relative to their source file, never the output.
            target = (self.source.parent / unquote(url.path)).resolve()
            if target in self.registry:
                path = self.registry[target] + ".html"
            else:
                try:
                    relative = target.relative_to(ROOT).as_posix()
                except ValueError as exc:
                    raise ValueError(f"Link escapes repository in {self.source}: {original}") from exc
                if not target.exists():
                    raise ValueError(f"Missing source link in {self.source}: {original}")
                path = f"{REPOSITORY}/blob/main/{quote(relative, safe='/')}"
                if element.tag == "img":
                    path += "?raw=true"
            rewritten = urlsplit(path)
            element.set(attribute, urlunsplit((rewritten.scheme, rewritten.netloc, rewritten.path, url.query or rewritten.query, url.fragment)))


class LocalLinksExtension(Extension):
    def __init__(self, source: Path, registry: dict[Path, str]):
        self.source = source
        self.registry = registry
        super().__init__()

    def extendMarkdown(self, md):
        md.treeprocessors.register(LocalLinks(md, self.source, self.registry), "site_links", 1)


def template(name: str, **values: str) -> str:
    result = (SITE / "templates" / f"{name}.html").read_text(encoding="utf-8")
    for key, value in values.items():
        result = result.replace(f"%%{key}%%", value)
    unresolved = re.findall(r"%%[A-Z_]+%%", result)
    if unresolved:
        raise ValueError(f"Unresolved tokens in {name}: {', '.join(unresolved)}")
    return result


def page(slug: str, title: str, description: str, content: str, section: str, body_class: str) -> None:
    values = {f"ACTIVE_{name}": 'aria-current="page"' if name == section else "" for name in ("HOME", "GUIDE", "DOCS", "GALLERY")}
    for kind in ("css", "js"):
        digest = sha256((SITE / "assets" / f"site.{kind}").read_bytes()).hexdigest()[:12]
        values[f"{kind.upper()}_URL"] = f"assets/site.{kind}?v={digest}"
    html = template("base", TITLE=escape(title), DESCRIPTION=escape(description, quote=True), BODY_CLASS=body_class,
                    CONTENT=content, CANONICAL=CANONICAL + ("" if slug == "index" else f"{slug}.html"), **values)
    (OUTPUT / f"{slug}.html").write_text(html, encoding="utf-8")


def sidebar(guides: list[Guide], current: str) -> str:
    links = []
    for guide in guides:
        active = ' aria-current="page"' if guide.slug == current else ""
        links.append(f'<a href="{guide.slug}.html"{active}>{escape(guide.title)}</a>')
    return ('<p class="sidebar-title">Player guide</p>'
            '<button class="guide-menu-toggle" type="button" aria-expanded="true" '
            'aria-controls="guide-navigation" hidden>Browse guides <span aria-hidden="true">+</span></button>'
            '<nav id="guide-navigation">' + "\n".join(links) + '<a href="docs.html">All guides</a></nav>')


def build() -> None:
    guides = source_guides()
    registry = {(ROOT / guide.source).resolve(): guide.slug for guide in guides}
    # Only this generated directory is replaced. Source assets stay untouched.
    if OUTPUT.exists():
        shutil.rmtree(OUTPUT)
    OUTPUT.mkdir(parents=True)
    shutil.copytree(SITE / "assets", OUTPUT / "assets")
    (OUTPUT / ".nojekyll").touch()

    cards = []
    for guide in guides:
        source = ROOT / guide.source
        text = source.read_text(encoding="utf-8")
        md = markdown.Markdown(extensions=["toc", "tables", "fenced_code", LocalLinksExtension(source, registry)],
                               extension_configs={"toc": {"toc_depth": "2-3", "permalink": False}}, output_format="html")
        rendered = md.convert(text)
        body = ('<div class="docs-layout wrap"><aside class="docs-sidebar" aria-label="Documentation">'
                + sidebar(guides, guide.slug) + '</aside><article class="prose">'
                + '<a class="back-link" href="docs.html">All guides</a>' + rendered
                + '</article><aside class="toc" aria-label="On this page"><p class="sidebar-title">On this page</p>'
                + md.toc + '</aside></div>')
        section = "GUIDE" if guide.slug in {"get-started", "play"} else "DOCS"
        page(guide.slug, guide.title, guide.description, body, section, "article-page")
        topics = " ".join(re.findall(r"^#{1,6}\s+(.+)$", text, re.MULTILINE))
        search = escape(f"{guide.title} {guide.description} {guide.category} {topics}".lower(), quote=True)
        cards.append(f'<a class="doc-card" data-search="{search}" href="{guide.slug}.html">'
                     f'<span class="doc-category">{escape(guide.category)}</span><h2>{escape(guide.title)} '
                     f'<span aria-hidden="true">↗</span></h2><p>{escape(guide.description)}</p></a>')

    provenance = json.loads((SITE / "assets/gallery/provenance.json").read_text(encoding="utf-8"))
    gallery = []
    for shot in provenance["screenshots"]:
        path = "assets/gallery/" + shot["file"]
        caption = escape(shot["caption"], quote=True)
        gallery.append(f'<figure class="gallery-item"><a href="{path}" class="gallery-open" data-caption="{caption}">'
                       f'<img src="{path}" width="1280" height="720" loading="lazy" alt="{escape(shot["alt"], quote=True)}"></a>'
                       f'<figcaption><h2>{escape(shot["title"])}</h2><p>{caption}</p></figcaption></figure>')

    page("index", "Play Ultrapool with friends", "Steam multiplayer for 2–8 players. Share a run, race another table, or chase the high score.", template("home"), "HOME", "home-page")
    page("docs", "Player guide", "How to install Ultrapool Together, play with friends, and make the most of your build.", template("docs", DOC_CARDS="\n".join(cards)), "DOCS", "docs-page")
    page("gallery", "Screenshots", "Take a look at Ultrapool Together’s lobbies, shops, and tables.", template("gallery", GALLERY_ITEMS="\n".join(gallery)), "GALLERY", "gallery-page")


class PageAudit(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.ids: set[str] = set()
        self.links: list[str] = []
        self.errors: list[str] = []
        self.heading_count = 0
        self.has_title = False
        self.has_language = False

    def handle_starttag(self, tag, attributes):
        attrs = dict(attributes)
        if attrs.get("id"):
            if attrs["id"] in self.ids:
                self.errors.append(f"Duplicate id: {attrs['id']}")
            self.ids.add(attrs["id"])
        if tag == "h1":
            self.heading_count += 1
        if tag == "title":
            self.has_title = True
        if tag == "html":
            self.has_language = bool(attrs.get("lang"))
        for attribute in ("href", "src", "poster"):
            if attrs.get(attribute):
                self.links.append(attrs[attribute])
        if tag == "img" and "alt" not in attrs:
            self.errors.append("Image missing alt text")


def check() -> None:
    documents: dict[Path, PageAudit] = {}
    errors = []
    for path in OUTPUT.glob("*.html"):
        audit = PageAudit()
        text = path.read_text(encoding="utf-8")
        audit.feed(text)
        if re.search(r"%%[A-Z_]+%%", text):
            audit.errors.append("Unresolved template token")
        if audit.heading_count != 1:
            audit.errors.append(f"Expected one h1; found {audit.heading_count}")
        if not audit.has_title or not audit.has_language:
            audit.errors.append("Missing document title or language")
        documents[path.resolve()] = audit
        errors.extend(f"{path.name}: {error}" for error in audit.errors)
    if not documents:
        errors.append("No HTML pages generated")

    def check_reference(source: Path, reference: str) -> None:
        url = urlsplit(reference)
        if url.scheme or url.netloc:
            if url.scheme not in {"http", "https", "mailto", "tel", "data"}:
                errors.append(f"{source.name}: unsupported URL {reference}")
            return
        if url.path.startswith("/"):
            errors.append(f"{source.name}: root-relative URL breaks project Pages: {reference}")
            return
        target = (source.parent / unquote(url.path)).resolve() if url.path else source.resolve()
        if not target.is_relative_to(OUTPUT.resolve()) or not target.is_file():
            errors.append(f"{source.name}: missing local target {reference}")
        elif url.fragment and target in documents and unquote(url.fragment) not in documents[target].ids:
            errors.append(f"{source.name}: missing anchor {reference}")

    for path, audit in documents.items():
        for reference in audit.links:
            check_reference(path, reference)
    for path in (OUTPUT / "assets").rglob("*.css"):
        for reference in re.findall(r"url\(\s*['\"]?([^)'\"\s]+)", path.read_text(encoding="utf-8")):
            check_reference(path, reference)
    if errors:
        raise ValueError("Site integrity failed:\n" + "\n".join(errors))
    print(f"Checked {len(documents)} pages: local links, anchors, images, assets, and template integrity pass.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Build and validate local links, anchors, images, and templates.")
    args = parser.parse_args()
    build()
    if args.check:
        check()
    print(f"Built website: {OUTPUT}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(str(error))

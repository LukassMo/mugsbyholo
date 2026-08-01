# mugsbyholo.de

Static website for **MugsByHolo** — personalised mugs. Hosted on GitHub Pages, served from the
`main` branch root (no build step, no Actions workflow).

## Structure

```
.
├── index.html          # Landing page
├── designer/index.html # Tassen-Designer (self-contained, from kunden-designer-v29.html)
├── impressum.html      # Impressum (§ 5 DDG)
├── datenschutz.html    # Datenschutzerklärung (Art. 13 DSGVO)
├── assets/
│   ├── seite.css       # Shared styles for impressum + datenschutz
│   ├── fonts/          # Self-hosted Caveat + Patrick Hand (latin subset)
│   ├── favicon.png     # 512×512
│   ├── logo-stacked.png, mark.png, banner.png
├── CNAME               # mugsbyholo.de
├── .nojekyll           # Serve files as-is, skip Jekyll
├── robots.txt
└── sitemap.xml
```

## Things to check before announcing the site

- **Etsy link.** There are three outbound shop links, each marked with
  `<!-- ETSY-LINK: hier die echte Shop-Adresse eintragen -->` — one in `index.html` (hero CTA)
  and two in `designer/index.html` (header line, and the shop card in step 3). They all point at
  `https://www.etsy.com/de/shop/MugsByHolo` — a guess based on the planned shop name.
  Replace all three with the real URL once the shop is live:
  `grep -rn "etsy.com/de/shop" .`
- **Kleinunternehmer.** `impressum.html` states § 19 UStG small-business status. Confirm that
  matches your registration, or delete that section.

## Updating the designer

The designer is a single self-contained HTML file (fonts embedded as base64, no network calls).
To ship a new version, overwrite `designer/index.html`, then re-apply these local edits:

1. The footer hoster line must say **GitHub Pages, GitHub Inc., USA** (the original file says
   Cloudflare Pages) and carry the links to `/impressum.html` and `/datenschutz.html`.
2. The `<h1>` links back to `/`, and the `<head>` has the favicon and description tags.
3. The header line "Kauf & Zahlung laufen über Etsy" is an `<a class="spec">` to the shop.
4. Step 3 has the `.shop-karte` block (Etsy CTA) plus its CSS, and `btn-export` highlights that
   card via `.leuchtet` after saving.
5. An empty "Große Zeile" must stay empty — the original file falls back to the birth year
   (`if (!sV.hero …) sV.hero=String(d.jahr)` in `aktualisiere()`, twice: front and back).
   The `level` layout's corner brackets are likewise skipped when the hero line is empty.
6. The whole German/English layer (see below) and the `NAEHER_PT` sheet layout.

## German / English

The designer switches language in the browser; there is no second HTML file. Two flag buttons
sit in the header, the choice is remembered in `localStorage` under `mbh-sprache`, and first-time
visitors get English unless `navigator.language` starts with `de`.

Adding or changing a text:

- **Static markup** — put `data-i18n="key"` on the element (or `data-i18n-ph` for a placeholder)
  and add `key` to **both** tables in `TEXTE`. The German text stays in the HTML as the fallback
  that shows before JavaScript runs.
- **Strings built in JavaScript** — write `T('key')`, never a bare string.
- **The phrases printed on the mug** live in `PRESET_TEXTE.de` / `.en`, keyed by layout. `nm` must
  be present in both languages or absent in both — its presence is what shows and hides the name
  line. Placeholders (`{name}`, `{jahr}`, `{alter}`, `{initial}`) must match between languages.
- Anything the user typed is left alone on a language switch; only untouched preset fields follow
  the new language.

A missing English key silently falls back to German rather than breaking the page, so check both
tables after editing. `scripts/` has no test runner — the checks used when this was built were a
key-coverage script and a headless Edge run (`--headless=new --dump-dom`) that clicks both flags.

`NAEHER_PT` (default 30) moves the back side that many typographic points closer to the text side,
in both the print file and the preview crop, via the shared `seitenLayout()`. Set it to 0 for the
old spacing, or negative to push the two sides further apart.

## Deploying

```sh
git add -A && git commit -m "..." && git push
```

GitHub Pages redeploys automatically, usually within a minute.

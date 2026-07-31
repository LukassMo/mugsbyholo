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

- **Etsy link.** `index.html` has one outbound shop link, marked with
  `<!-- ETSY-LINK: hier die echte Shop-Adresse eintragen -->`. It currently points at
  `https://www.etsy.com/de/shop/MugsByHolo` — a guess based on the planned shop name.
  Replace it with the real URL once the shop is live.
- **Kleinunternehmer.** `impressum.html` states § 19 UStG small-business status. Confirm that
  matches your registration, or delete that section.

## Updating the designer

The designer is a single self-contained HTML file (fonts embedded as base64, no network calls).
To ship a new version, overwrite `designer/index.html`, then re-apply the two local edits:

1. The footer hoster line must say **GitHub Pages, GitHub Inc., USA** (the original file says
   Cloudflare Pages) and carry the links to `/impressum.html` and `/datenschutz.html`.
2. The `<h1>` links back to `/`, and the `<head>` has the favicon and description tags.

## Deploying

```sh
git add -A && git commit -m "..." && git push
```

GitHub Pages redeploys automatically, usually within a minute.

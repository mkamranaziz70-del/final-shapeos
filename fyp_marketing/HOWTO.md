# ShapeOS Standee & Brochure

Two print-ready HTML files for the FYP expo.

| File             | Page size in CSS  | Approx mm (for print dialog) |
|------------------|-------------------|------------------------------|
| `standee.html`   | 900 x 2550 px     | 238 mm x 675 mm              |
| `brochure.html`  | 1280 x 880 px     | 339 mm x 233 mm  (2 pages)   |

Both files use `@page` plus a `@media print` block so the layout stays locked when exporting. The previous duplicate-ribbon issue is gone now that the page margin no longer pushes content past the page boundary.

## Export to PDF (Chrome or Edge)

1. Open the HTML file in Chrome or Edge.
2. Press `Ctrl + P`.
3. Destination -> **Save as PDF**.
4. Paper size -> **Custom**, then enter the size from the table above.
   - Standee: 238 mm by 675 mm
   - Brochure: 339 mm by 233 mm
5. Layout -> **Portrait** for the standee, **Landscape** for the brochure.
6. Margins -> **None**.
7. Scale -> **100** (do not pick "Fit to page" or "Default").
8. Options -> **Background graphics ON**.
9. Save.

If the printer expects standard sizes only, send the PDF to a print shop and tell them the final size you want it printed at. Most expo standees are produced as a 2 ft by 5 ft roll-up; the file scales cleanly because the layout is vector and the brand logos are SVG.

## Headless one-liner

If you have Chrome installed and want a fully automated export from PowerShell:

```powershell
& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless --disable-gpu `
  --print-to-pdf="ShapeOS-Standee.pdf" --no-pdf-header-footer `
  "file:///c:/FlutterProjects/shapeosfinal/fyp_marketing/standee.html"

& "C:\Program Files\Google\Chrome\Application\chrome.exe" --headless --disable-gpu `
  --print-to-pdf="ShapeOS-Brochure.pdf" --no-pdf-header-footer `
  "file:///c:/FlutterProjects/shapeosfinal/fyp_marketing/brochure.html"
```

Headless Chrome honours the `@page` size in the CSS automatically, so this avoids fiddling with the print dialog.

## Editing the names

- Group members and supervisor are inside the `.team` block (`standee.html`) and the `.ribbon` block (`brochure.html`).
- Brand colour stack: `#122a55` deep navy, `#0b6a8c` teal, `#00c2a8` mint accent. Replace globally to recolour.
- Logos sit in `assets/images/` (Air University, Department of Computer Science, ShapeOS).

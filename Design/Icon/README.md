# Tabsome icon sources

| File | What it is |
|---|---|
| `Tabsome-appicon.svg` | Flat app icon artwork (824 px body on a 1024 canvas, gradient, sheen, outline). |
| `Tabsome-appicon-1024.png` | Rendered 1024 px app icon with its drop shadow; the PNG sizes in `Tabsome/Assets.xcassets/AppIcon.appiconset` match it. |
| `Tabsome.icns` | The same PNG set as an `.icns` (all ten sizes), built with `iconutil`. |
| `Tabsome-menubar.svg` / `.pdf` | Menu bar template glyph, black on transparent, 16×16 pt. |

The app's primary icon is `Tabsome/AppIcon.icon` (Icon Composer). It uses the gradient as the fill and
`Assets/glyph.svg` (the same glyph, scaled so it keeps its share of the icon) as a glass layer; macOS
draws the shape, highlights, shadow, and the dark and tinted versions. Open it in Icon Composer
(Xcode › Open Developer Tool › Icon Composer) to tweak it.

**Glyph seam fix (2026-10-20):** the window outline and the T stem used to be two shapes that touched,
which left a faint antialiasing line where they met. The SVGs now use one path. In the PNGs, only the
pixel row on that seam, within the stem's width, was repaired; every other pixel is unchanged. The menu
bar PDF was regenerated from the single path at the correct 16×16 pt (it had been exported at 12×12 pt).

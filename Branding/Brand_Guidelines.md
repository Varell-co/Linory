# Linory — Brand Guidelines

**Brand identity v1.0 · A Varell product · November 2026**

## 1. Positioning

**Name:** Linory  
**Descriptor:** Floating synced lyrics for macOS.  
**Tagline:** Lyrics in your flow.  
**Endorsement:** A Varell product.  
**Category:** Native macOS music/lyrics utility.  
**Personality:** Quiet, precise, light, modern, dependable, soft-edged.

Linory is a companion, not another music player. Its identity should suggest lyrics in motion without competing with the content. The approved motif is **two fluid, offset ribbons**, rendered as a polished native macOS app icon.

## 2. Product truth — current prototype

The repository README describes a small native macOS app that displays synchronized lyrics for tracks playing in the Spotify desktop application. A floating overlay highlights the active line while preserving surrounding lines. Users can reposition it, change typography and opacity, configure timing offset, and control it from the macOS menu bar. Lyrics come from LRCLIB, not Spotify; this is an early prototype, not a broadly tested or notarized public release.

Do not claim Apple Music support, other platforms, local/offline lyrics, official Spotify affiliation, or completed feature work not present in the README. Revisit marketing copy as the product evolves. Repository: https://github.com/JulianRudrich/LyricsOverlay/blob/main/README.md

## 3. Brand architecture

- **Varell** is the parent studio / publisher.
- **Linory** is the product users see in the Dock, menu bar, onboarding, and product pages.
- **A Varell product** is a discreet endorsement for About panels, websites, decks, and README materials.
- Do not put the Varell name inside the lyric overlay itself or in the macOS menu-bar glyph.
- The endorsement included in this kit is typeset and is **not** a replacement for Varell's original bespoke wordmark.

## 4. Signature logo

The master symbol consists of **two tapering blue wave ribbons**, both drawn as fully editable SVG paths. Their offset embodies synchronized lyric lines, gentle movement, and an unobtrusive floating layer. Use the vertical gradient version for app/marketing; use flat one-color versions for small, monochrome, technical, and contrast-critical use.

- Master symbol: `02_Logos/Symbol/Linory_Symbol_Gradient.svg`.
- Primary light lockup: `02_Logos/Lockups/Linory_Horizontal_Light.svg`.
- Primary dark lockup: `02_Logos/Lockups/Linory_Horizontal_Dark.svg`.
- Endorsed light/dark lockups: `Linory_By_Varell_*.svg`.
- Wordmark-only: outlined SVGs in `02_Logos/Wordmark/` (do not require fonts).

### Clear space and minimum sizes

- Keep at least **0.3× symbol height** of empty space around the symbol or lockup.
- Digital wordmark-only minimum: **100 px width**.
- Horizontal lockup minimum: **160 px width**; use wordmark-only beneath that.
- App icon: always retain the tile shape and central wave spacing; export via the provided 1024 px master.
- Menu-bar glyph: use the purpose-designed `04_Menu_Bar/Linory_MenuBar_Template_Black.svg`, not a tiny colored app icon.

### Backgrounds

- On white or light backgrounds, use the Ink wordmark + gradient symbol.
- On Ink/Graphite backgrounds, use the white wordmark + gradient symbol.
- For single-color applications, use the Ink/White/Graphite symbol and corresponding monochrome wordmark.
- Avoid adding outlines, drop shadows, bevels or alternate gradients to the waves outside app-icon contexts.
- Do not rotate, stretch, mirror or split the two ribbons.

## 5. Color system

| Role | Hex | Usage |
|---|---|---|
| Ink | `#14161B` | Main text, dark tiles |
| Graphite | `#303640` | Dark surfaces, secondary icon color |
| Silver | `#BCC5D2` | Soft metal/material cues |
| Mist | `#F2F4F7` | Backgrounds, light UI |
| Accent | `#B1C5E5` | Quiet highlighted surfaces |
| Wave Blue | `#4385EF` | Main lower-wave saturated tone |
| Wave Mid | `#76A3EE` | Wave transitions |
| Wave Light | `#AFC9F1` | Upper-wave light tone |
| Wave Deep | `#557FCE` | Upper-wave deep tone |
| Secondary Text | `#657082` | Muted labels and support copy |
| Border | `#D9E1EC` | UI separators and subtle outlines |

**Gradient direction:** each wave transitions along its length; upper light-to-deep blue, lower strong-to-soft blue. Avoid rainbow or neon alternatives. Use Ink for ordinary text, not the decorative Accent blue.

## 6. Typography

- **macOS app UI:** the system San Francisco font (SwiftUI `.system(...)` / AppKit system font). Use Regular, Medium, Semibold. This keeps a native Apple feel.
- **Marketing/site:** Inter or Inter Display as a close, redistributable-free approximation of the brand-board typesetting. Prefer substantial but restrained headings, tight hierarchy, and generous space.
- **Logo:** supplied with glyphs converted to paths, so no font installation is required. Editable-text variants are included separately and can differ marginally between machines.
- **Hierarchy:** headline 40–72 px in large marketing compositions; body 16–18 px; small labels 11–13 px. Actual app sizing should respect user settings and Dynamic Type/readability requirements where applicable.
- Avoid all-uppercase display headlines. Uppercase is appropriate only for quiet brand endorsement and technical labels.

## 7. macOS UI / materials

- Content first: lyrics must dominate the floating window.
- The active line is high-contrast Semibold; adjacent lines are quieter but still readable.
- UI surfaces use native macOS materials when practical, with adjustable opacity (a current prototype feature).
- Prefer 16–24 px rounding for overlays, not bulky chrome, and keep controls unobtrusive.
- Don't rely on blur for sufficient contrast; verify appearance over light and dark desktop content.
- No permanently bright, distracting glow; shadows should be subtle.
- Use reduced-motion-aware line transitions; no endless decorative motion.
- The sample panels in this kit are **conceptual visuals**, not confirmed screenshots of the implementation.

## 8. App icon

- Approved foundation: two offset blue ribbons centered on softly rounded light macOS tile.
- Primary: `03_App_Icon/SVG/Linory_AppIcon_Light.svg`.
- Dark/blue alternates are included for presentations and theme testing; do not randomly switch the installed app icon by theme without a product decision.
- Use the ready-made `03_App_Icon/Linory.icns`, or create a fresh file from the supplied `Linory.iconset`. PNGs are premade in all common iconset sizes.
- macOS export (on a Mac): `iconutil -c icns Linory.iconset -o Linory.icns`.

## 9. Menu bar

- A template image uses **one flat silhouette and transparency**, letting macOS adapt it to active appearance. Use the black SVG as source and set the NSImage `isTemplate = true` after rendering as a supported macOS image format.
- Keep the glyph visually compact and centered at approximately 16–20 points wide, adjusting to menu-bar height.
- Do not use the gradient in the system menu bar.

## 10. Layout and image treatment

- Generous white/Mist margins, graphite type, soft blue atmosphere.
- A single dominant product visual per composition; more than one focal point makes a utility look noisy.
- Prefer realistic, calm macOS app/UI contexts. Avoid unlicensed music assets and misleading fake integration indicators.
- Promotional waves can echo the symbol, but the logo shape itself remains fixed.

## 11. Brand voice

**Tone:** precise, spare, quietly confident, helpful.  
**Preferred:** “Lyrics in your flow.” / “Floating synced lyrics for macOS.”  
**Avoid:** “Revolutionize music,” “Spotify-powered lyrics,” “works with every app,” or unsupported claims.

### Usage examples

- Website hero: **Linory** / **Lyrics in your flow.** / Floating synced lyrics for macOS.
- About panel: **Linory** / A Varell product.
- App store/README short description: A native macOS utility for floating, synchronized lyrics while you work.
- Secondary supporting copy: Keep the words in view without breaking your focus.

## 12. Licensing and diligence

This kit consists of newly drafted vector artwork inspired by the approved visual direction. The original preview/render is a **concept reference**, not a pixel-perfect vector source. The name and symbol have **not** been conclusively cleared for trademark use or third-party similarities. Check relevant trademark registers and existing software icons prior to commercial launch. Linory is not affiliated with Spotify or LRCLIB. Apple/SF Pro names are referenced for UI conventions; **no font files are included**.

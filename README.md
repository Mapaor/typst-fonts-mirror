# What is this?
This repository contains a comprehensive list of the fonts available in the Typst web app, their download and license links, and other useful information.

A few of those fonts don't have a direct download link, therefore the existence of this repository. 

The fonts with a missing direct download link are:
- Comic Neue Angular
- Infini
- Infini Picto
- Reforma 1918
- Reforma 1969
- Reforma 2018

The fonts which are google fonts with a `[fonts.google](https://fonts.google.com/download?*` link, that is they can be manually downloaded but not programmatically are:
- Allura
- Atkinson Hyperlegible
- Atkinson Hyperlegible Mono
- Atkinson Hyperlegible Next
- Atma
- Barlow
- Buenard
- Cantarell
- Cascadia Code
- Cascadia Mono
- Clicker Script
- Comic Neue
- Crimson Pro
- DM Mono
- DM Sans
- DM Sans 9pt
- DM Serif Display
- DM Serif Text
- EB Garamond
- Exo 2
- Fira Mono
- Fira Sans
- GFS Neohellenic
- GFS Neohellenic Math
- HK Grotesk
- IBM Plex Mono
- IBM Plex Sans
- IBM Plex Serif
- Inconsolata
- Inria Sans
- Inria Serif
- Inter
- Lato
- Libre Barcode 128
- Libre Barcode 128 Text
- Libre Baskerville
- Manrope
- Merriweather
- Merriweather 7pt
- Merriweather Sans
- Noto Color Emoji
- Noto Emoji
- Noto Sans
- Noto Sans Display
- Noto Serif
- Noto Serif Display
- Old Standard
- OldStandard-Math
- Permanent Marker
- PT Mono
- PT Sans
- PT Sans Caption
- PT Serif
- Public Sans
- Roboto Mono
- Roboto Serif
- Roboto Serif 20pt
- Roboto Slab
- Source Code Pro
- Source Sans Pro
- Source Serif Pro
- Spectral
- STIX Two Math
- STIX Two Text
- Syne
- Syne Mono
- Syne Tactile
- Vollkorn

This repository redistributes all these font files and their respective licenses as [GitHub Releases](https://github.com/Mapaor/typst-fonts-mirror/releases) artifacts.

The goal is to allow an automated script to fetch `fonts_index.json` and from i t download all the font files and licenses to a local directory. 

I made this repo to allow the `CACHE_ALL_FONTS` option in [`typst-api`](https://github.com/Mapaor/typst-api).

## Scripts
This repo also contains the following useful scripts
- `check-font-links.ps1`: To ensure all the links in `fonts_index.json` are reachable (an HTTP request to dtem returns 200 Ok).
- `get-google-fonts-links.ps1`: To generate `google_fonts.json` from `fonts_index.json`.
- `download_google_fonts.js`: To download all the fonts from `google_fonts.json` using Playwright (Node package).
- `download-fonts.ps1`: To download the rest of the fonts. Excluding google fonts and the 6 fonts that had to be downloaded manually (ComicNeue-Angular, Infini, Infini-Picto, Reforma 1918, Reforma 1969 and Reforma 2018).
- `download-selected-fonts.ps1`: To only download a specific list of fonts, useful for testing if their download urls work or not.
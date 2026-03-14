# WikipediaScraper

A Swift command-line tool that converts Wikipedia person articles into standards-compliant **GEDCOM 7.0** genealogy files, importable into Mac Family Tree 11, Gramps, RootsMagic, and other genealogy applications.

## Features

- Parses Wikipedia infoboxes (royalty, officeholder, biography templates) into structured genealogy data
- Outputs GEDCOM 7.0 with full compliance: correct xrefs, UTF-8, CONT line-splitting, proper tag hierarchy
- Accepts **multiple Wikipedia URLs** in a single run — all persons land in one GEDCOM file
- Automatically fetches Wikipedia data for **referenced people** (spouses, parents, children) one level deep — no manual lookups needed
- Persons referenced by multiple input URLs are **deduplicated and properly linked** — one INDI record, one FAM record, shared across all contexts
- Downloads portrait images from Wikimedia and packages them into a **GEDZIP archive** (`.zip` / `.gdz`)
- Optionally downloads **every article image** into the archive (`--allimages`)
- Appends full **Wikipedia article sections as NOTEs** (`--notes`)
- Emits titled positions (reign, office) as **GEDCOM EVEN with TYPE "Nobility title"** for timeline display
- Predecessor/successor links use **ASSO + RELA** (Influential Persons) for compatible apps
- Source citations use **SOUR.WWW** (top-level domain) + **PAGE** (specific article URL) + **DATA.TEXT** (article extract)
- Field-mapping diagnostic report (`--mappings`) shows exactly how each infobox field was interpreted

---

## Requirements

- macOS 13 or later
- Swift 5.9+ (ships with Xcode 15+)
- Internet connection (Wikipedia APIs)

---

## Installation

### Build from source

```bash
git clone https://github.com/psteinauer/WikipediaScraper.git
cd WikipediaScraper
make install          # builds release binary → /usr/local/bin/WikipediaScraper
```

Or install to a custom location:

```bash
make install INSTALL_PREFIX=~/.local/bin
```

### Build debug binary (for development)

```bash
make build
# binary: .build/debug/WikipediaScraper
```

### Open in Xcode

```bash
make xcode
```

---

## Usage

```
WikipediaScraper [options] <URL> [<URL> ...]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `<URL> ...` | One or more full Wikipedia article URLs |

### Options

| Flag / Option | Short | Description |
|---------------|-------|-------------|
| `--output <path>` | `-o` | Override output file path |
| `--verbose` | `-v` | Print progress to stderr |
| `--preflight` | `-p` | Write GEDCOM to stdout (no file written) |
| `--zip` | `-z` | Create GEDZIP archive (`.zip` default, use `--output` for `.gdz`) |
| `--mappings` | `-m` | Print field-mapping table; no GEDCOM produced |
| `--notes` | `-n` | Append Wikipedia article sections as NOTE records |
| `--allimages` | `-a` | Download all article images into GEDZIP (implies `--zip`) |
| `--nopeople` | | Only create records for the URLs passed; skip referenced-person fetching |
| `--config <path>` | | Use a specific `.wikipediascraperrc` file |
| `--help` | `-h` | Show help |
| `--version` | | Show version |

### Output modes (mutually exclusive)

| Mode | Default output |
|------|----------------|
| Default | `<ArticleTitle>.ged` in current directory |
| `--preflight` | stdout |
| `--zip` / `--allimages` | `<ArticleTitle>.zip` (or `.gdz` via `--output`) |
| `--mappings` | stdout (diagnostic table, no GEDCOM) |

When multiple URLs are provided, the default output filename is `<FirstTitle>_et_al.ged` / `.zip`.

---

## Examples

### Single person, default `.ged` output

```bash
WikipediaScraper https://en.wikipedia.org/wiki/George_Washington
# → George_Washington.ged
```

### Custom output path

```bash
WikipediaScraper --output ~/genealogy/washington.ged \
    https://en.wikipedia.org/wiki/George_Washington
```

### GEDZIP archive with portrait image

```bash
WikipediaScraper --zip https://en.wikipedia.org/wiki/Elizabeth_II
# → Elizabeth_II.zip  (gedcom.ged + media/Elizabeth_II.jpg)
```

### GEDZIP with `.gdz` extension

```bash
WikipediaScraper --zip --output royals/elizabeth.gdz \
    https://en.wikipedia.org/wiki/Elizabeth_II
```

### Inspect GEDCOM output without writing a file

```bash
WikipediaScraper --preflight https://en.wikipedia.org/wiki/Napoleon
```

### Include full article text as notes

```bash
WikipediaScraper --preflight --notes https://en.wikipedia.org/wiki/Napoleon
```

### Download all article images into the archive

```bash
WikipediaScraper --allimages https://en.wikipedia.org/wiki/Queen_Victoria
# → Queen_Victoria.zip  (gedcom.ged + portrait + all article images)
```

### Diagnostic field-mapping table

```bash
WikipediaScraper --mappings https://en.wikipedia.org/wiki/Napoleon
```

### Multiple people in one file

```bash
WikipediaScraper --zip \
    https://en.wikipedia.org/wiki/Queen_Victoria \
    https://en.wikipedia.org/wiki/Prince_Albert
# → Queen_Victoria_et_al.zip
# Victoria and Albert share one FAM record; their mutual references are deduplicated.
```

### Verbose output

```bash
WikipediaScraper --verbose --zip https://en.wikipedia.org/wiki/Napoleon
```

---

## Configuration file — `.wikipediascraperrc`

WikipediaScraper supports a plain-text configuration file that lets you customise how Wikipedia infobox fields are mapped to GEDCOM facts and events, and add mappings for fields that the built-in parser doesn't handle.

### File locations

The tool searches for the config file in this order:

1. Path supplied with `--config <path>`
2. `.wikipediascraperrc` in the **current working directory**
3. `~/.wikipediascraperrc` in your **home directory**

The first file found is used; the others are ignored.

### File format

The file uses a simple INI-style format with two sections: `[facts]` and `[events]`. Lines beginning with `#` or `;` are comments; blank lines are ignored.

```ini
# ~/.wikipediascraperrc

[facts]
# field_name = FACT TYPE display name
#
# Maps an infobox field to a GEDCOM FACT record.
# Each non-empty value (or list item) in the field becomes a separate FACT.
# Field names are the lowercase infobox parameter names with spaces → underscores.

party         = Political Party
house         = Royal House
awards        = Honour
religion      = Religious Affiliation
alma_mater    = Education

[events]
# field_name = EVEN TYPE display name
#
# Maps an infobox field to a GEDCOM EVEN record.
# The field value is parsed as a date if possible; otherwise stored as a note.
# One EVEN record is produced per field.

coronation          = Coronation
inauguration_date   = Inauguration
```

### How overrides work

| Scenario | Behaviour |
|----------|-----------|
| Field already handled by built-in code (e.g. `party`, `awards`) | RC display name replaces the built-in default |
| Field not handled by built-in code (e.g. `alma_mater`) | New FACT or EVEN records are added for any matching infobox field |
| Field present in RC but absent from the infobox | No output produced (silently skipped) |

### Built-in fields you can rename

These fields are processed by default. Add an entry to `[facts]` or `[events]` to change the display name:

| Section | Infobox field | Default display name |
|---------|--------------|----------------------|
| `[facts]` | `party` | `Political party` |
| `[facts]` | `house` / `dynasty` / `royal_house` | `House` |
| `[facts]` | `awards` | `Award` |
| `[facts]` | `branch` | `Military branch` |
| `[facts]` | `rank` | `Military rank` |
| `[facts]` | `allegiance` | `Allegiance` |
| `[facts]` | `service_years` | `Service years` |
| `[facts]` | `battles` / `battles/wars` | `Battle` |
| `[events]` | `coronation` | `Coronation` |

### George Washington example

George Washington's Wikipedia infobox contains a `party` field with the value `Independent`. The built-in mapping produces `FACT Independent / TYPE Political party`. To change the type label to `Political Party`:

```ini
# ~/.wikipediascraperrc

[facts]
party = Political Party
```

Running the tool now produces:

```
1 FACT Independent
2 TYPE Political Party
2 SOUR @S1@
```

To also capture his `alma_mater` field (not mapped by default):

```ini
[facts]
party      = Political Party
alma_mater = Education
```

This would produce a `FACT College of William & Mary / TYPE Education` record.

---

## GEDZIP archive structure

```
archive.zip (or .gdz)
├── gedcom.ged              GEDCOM 7.0 file (FILE tags use relative paths)
└── media/
    ├── Person_Name.jpg     Portrait downloaded from Wikimedia
    └── Image_Caption.jpg   Additional images (--allimages only)
```

---

## GEDCOM 7.0 output structure

Each person article produces the following GEDCOM records:

### Name records

The primary `NAME` record is taken from the **Wikipedia article title** (`summary.title` from the REST API), since that is the definitive, canonical identifier for the person. Additional name records are added for other names found on the page:

| NAME record | Source | Notes |
|------------|--------|-------|
| Primary `NAME` | Wikipedia article title | `GIVN` + `SURN` from infobox components |
| Additional `NAME` | Infobox `name` / `given_name` + `surname` | Added when structured infobox name differs from article title |
| `NAME TYPE birth` | `birth_name` | Birth / maiden name |
| `NAME TYPE aka` | Alternate names defined in infobox | |

**Examples:**

| Article title | Primary `NAME` | Additional `NAME` |
|--------------|----------------|-------------------|
| George Washington | `George Washington` | — (infobox name is identical) |
| Queen Victoria | `Queen Victoria` | `Victoria` (infobox `name` field) |
| Albert, Prince Consort | `Albert, Prince Consort` | `Albert /Saxe-Coburg and Gotha/` |

### INDI record

| GEDCOM tag | Source field | Notes |
|------------|-------------|-------|
| `NAME` | Wikipedia article title | `GIVN` + `SURN` subrecords; see Name records above |
| `NAME TYPE birth` | `birth_name` | Alternate name record |
| `SEX` | `gender`, `sex`, `pronouns` | Omitted when unknown |
| `BIRT` | `birth_date`, `birth_place` | With `DATE`, `PLAC`, `SOUR` |
| `DEAT` | `death_date`, `death_place`, `death_cause` | With `CAUS` subrecord |
| `BURI` | `burial_place`, `resting_place` | |
| `BAPM` | `baptism_date`, `baptism_place` | |
| `TITL` | `title`, `honorific_prefix`, `style`, etc. | Simple honorifics without date range |
| `EVEN … TYPE "Nobility title"` | `succession`, `reign`, `office`, `term_start/end` | One EVEN per reign/office, with `DATE FROM … TO` |
| `EVEN … TYPE "<name>"` | `coronation` | Custom events |
| `FACT … TYPE "<type>"` | `house`, `party`, `branch`, `rank`, `awards`, `battles` | One FACT per value |
| `OCCU` | `occupation`, `profession` | One tag per occupation |
| `NATI` | `nationality`, `citizenship` | |
| `RELI` | `religion`, `faith` | |
| `ASSO … RELA Predecessor/Successor` | `predecessor`, `successor` | Influential persons |
| `NOTE` | Wikipedia article sections | One NOTE per section (`--notes`) |
| `FAMS` | Spouse family links | |
| `FAMC` | Parent family link | |
| `SOUR` | Wikipedia article | `PAGE` = article URL, `DATA.TEXT` = excerpt |
| `OBJE` | Portrait + additional images | |

### FAM record

One `FAM` record per marriage, containing `HUSB`, `WIFE`, `MARR` (date + place), `DIV`, `CHIL`, and `SOUR`. When two input persons are married to each other, a single FAM record is shared — no duplication.

### SOUR record

One `SOUR` record per unique domain (e.g. one for all Wikipedia articles):

```
0 @S1@ SOUR
1 TITL Wikipedia
1 AUTH Wikipedia contributors
1 PUBL Wikimedia Foundation
1 WWW https://en.wikipedia.org/
1 DATE <today>
```

### OBJE record

Portrait and additional images are stored as `OBJE` records with `FILE` pointing to the relative path inside the GEDZIP archive (or the remote URL for plain `.ged` output).

---

## Referenced-person expansion

By default, when the tool parses a person's infobox, it extracts Wikipedia article links from family fields (spouses, children, father, mother, parents). It then automatically fetches each referenced person from Wikipedia and includes them as full INDI records — one level deep, without recursion.

Use `--nopeople` to disable this behaviour and only create records for the URLs explicitly passed on the command line. Referenced people not on the command line become minimal stub INDI records (name only). If two command-line URLs reference each other (e.g. a couple), they are still linked through a shared FAM record.

**Deduplication rules:**

- If a referenced person's article title matches a command-line person (by canonical title from the Wikipedia REST API), they share one INDI record
- If two command-line persons are married to each other, they share one FAM record, and both INDI records contain `FAMS` pointing to it
- If a child's infobox names the same parents as a command-line person's spouse, all three are linked through one FAM record

**What referenced persons get:**

| Feature | Primary (command-line) | Referenced (auto-fetched) |
|---------|----------------------|--------------------------|
| Full infobox parsing | ✓ | ✓ |
| Portrait download (`--zip`) | ✓ | ✓ |
| Article sections (`--notes`) | ✓ | — |
| All images (`--allimages`) | ✓ | — |

---

## Infobox field mapping

The tool handles two major Wikipedia infobox templates:

### `{{Infobox royalty}}`

| Infobox field | GEDCOM output |
|--------------|---------------|
| `succession` / `reign` | `EVEN TYPE "Nobility title"` with `DATE FROM … TO` |
| `coronation` | `EVEN TYPE "Coronation"` |
| `predecessor` / `successor` | `ASSO RELA Predecessor/Successor` |
| `house` / `dynasty` | `FACT TYPE "House"` |
| `spouse` (with `{{marriage|…}}`) | `FAM MARR DATE` |

### `{{Infobox officeholder}}`

| Infobox field | GEDCOM output |
|--------------|---------------|
| `office` / `term_start` / `term_end` | `EVEN TYPE "Nobility title"` with `DATE FROM … TO` |
| `preceded_by` / `succeeded_by` | `ASSO RELA Predecessor/Successor` |
| `party` | `FACT TYPE "Political party"` |

### `{{Infobox military person}}`

| Infobox field | GEDCOM output |
|--------------|---------------|
| `branch` | `FACT TYPE "Military branch"` |
| `rank` | `FACT TYPE "Military rank"` |
| `battles` | `FACT TYPE "Battle"` (one per battle) |
| `awards` | `FACT TYPE "Award"` (one per award) |
| `allegiance` | `FACT TYPE "Allegiance"` |
| `service_years` | `FACT TYPE "Service years"` |

### Date handling

Dates are parsed from a wide variety of Wikipedia formats:

| Input | GEDCOM output |
|-------|---------------|
| `24 May 1819` | `24 MAY 1819` |
| `{{birth date|1819|5|24}}` | `24 MAY 1819` |
| `c. 1066` / `circa 1066` | `ABT 1066` |
| `before 1200` | `BEF 1200` |
| `after 1400` | `AFT 1400` |
| `20 June 1837 – 22 January 1901` | `FROM 20 JUN 1837 TO 22 JAN 1901` |
| `{{reign|1837|6|20|1901|1|22}}` | `FROM 20 JUN 1837 TO 22 JAN 1901` |

---

## GEDCOM 7.0 compliance

| Feature | Handling |
|---------|---------|
| Character encoding | UTF-8 (no `CHAR` tag — mandatory and implicit in GEDCOM 7) |
| Line length | Max 255 bytes; overflow split with `CONT` (Unicode-aware byte boundary) |
| Xrefs | All `HUSB`, `WIFE`, `CHIL` point to real INDI records (no placeholders) |
| Unknown sex | `SEX` tag omitted (not all apps handle `SEX U`) |
| Multiple occupations | One `OCCU` tag per value |
| Web source | `SOUR.WWW` for top-level URL (GEDCOM 7 standard tag) |
| Source citation | `SOUR.PAGE` for specific article URL; `SOUR.DATA.TEXT` for excerpt |
| Multimedia | `OBJE.FILE` with relative paths in GEDZIP; remote URL for plain `.ged` |

---

## Source code layout

```
Sources/WikipediaScraper/
├── WikipediaScraperCommand.swift   Entry point, argument parsing, orchestration
├── WikipediaClient.swift           Wikipedia REST + MediaWiki API calls
├── InfoboxParser.swift             Wikitext infobox → PersonData extraction
├── DateParser.swift                Wikipedia date string → GEDCOMDate
├── PersonModel.swift               Data model (PersonData, SpouseInfo, PersonRef, …)
├── GEDCOMBuilder.swift             PersonData → GEDCOM 7.0 text
├── GEDZIPBuilder.swift             GEDCOM + media files → ZIP archive
└── MappingsReporter.swift          Diagnostic field-mapping table
```

---

## Build targets

| Command | Description |
|---------|-------------|
| `make build` | Debug binary (`.build/debug/WikipediaScraper`) |
| `make release` | Optimised release binary |
| `make install` | Build release and install to `/usr/local/bin` |
| `make install INSTALL_PREFIX=<dir>` | Install to custom directory |
| `make xcode` | Open package in Xcode |
| `make clean` | Remove build artifacts |
| `make test` | Smoke-test against George Washington article |

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | ≥ 1.3.0 | CLI argument / flag / option parsing |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | ≥ 0.9.19 | GEDZIP archive creation |

---

## Limitations

- English Wikipedia only (`en.wikipedia.org`)
- Infobox parsing covers the most common templates; unusual or highly customised infoboxes may produce incomplete data — use `--mappings` to diagnose
- Date parsing handles the most common Wikipedia date formats; highly non-standard formats fall back to an empty date
- Referenced-person expansion is one level deep; it does not recursively follow the family trees of fetched persons
- `--allimages` skips small images (< 100×100 px), icons, flags, logos, and other decorative images based on filename heuristics

---

## License

MIT

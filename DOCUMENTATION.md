# WikipediaScraper — Technical Documentation

This document covers the software architecture, data-flow pipelines, and module internals for the CLI tool, macOS app, and iPadOS app. It is intended for developers working on or extending the codebase.

---

## Table of Contents

1. [Project Structure](#1-project-structure)
2. [Architecture Overview](#2-architecture-overview)
3. [Core Library — WikipediaScraperCore](#3-core-library--wikipediascrapercore)
   - [PersonModel](#31-personmodel)
   - [WikipediaClient](#32-wikipediaclient)
   - [InfoboxParser](#33-infoboxparser)
   - [DateParser](#34-dateparser)
   - [GEDCOMBuilder](#35-gedcombuilder)
   - [GEDZIPBuilder](#36-gedzipbuilder)
   - [MappingsReporter](#37-mappingsreporter)
   - [ScraperConfig](#38-scraperconfig)
4. [Shared UI Library — WikipediaScraperSharedUI](#4-shared-ui-library--wikipediascrapersharedui)
   - [EditableTypes](#41-editabletypes)
   - [PersonEditorView](#42-personeditorview)
5. [CLI Tool — WikipediaScraper](#5-cli-tool--wikipediascraper)
   - [Entry Point and Argument Parsing](#51-entry-point-and-argument-parsing)
   - [CLI Data Flow](#52-cli-data-flow)
   - [Referenced-Person Expansion](#53-referenced-person-expansion)
   - [Deduplication](#54-deduplication)
   - [--nopeople Mode](#55---nopeople-mode)
6. [macOS App — WikipediaScraperApp](#6-macos-app--wikipediascraperapp)
   - [Scene and Window Setup](#61-scene-and-window-setup)
   - [App Data Flow](#62-app-data-flow)
   - [PersonViewModel](#63-personviewmodel)
   - [ContentView](#64-contentview)
   - [Export Paths](#65-export-paths)
7. [iPadOS App — WikipediaScraperIPad](#7-ipados-app--wikipediascraperipad)
   - [Scene Setup](#71-scene-setup)
   - [Platform Compilation Strategy](#72-platform-compilation-strategy)
   - [iPadPersonViewModel](#73-ipadpersonviewmodel)
   - [iPadContentView](#74-ipadcontentview)
   - [Export Paths](#75-export-paths)
8. [Key Algorithms](#8-key-algorithms)
   - [Infobox Extraction](#81-infobox-extraction)
   - [Date Parsing](#82-date-parsing)
   - [GEDCOM Name Construction](#83-gedcom-name-construction)
   - [Xref Allocation and Deduplication](#84-xref-allocation-and-deduplication)
9. [GEDCOM 7.0 Output Reference](#9-gedcom-70-output-reference)
10. [Configuration System](#10-configuration-system)
11. [Icon Generation](#11-icon-generation)

---

## 1. Project Structure

```
WikipediaScraper/
├── Package.swift                      SPM manifest — five targets
├── Makefile                           Build, install, app-bundle, ipad, test targets
├── make_icon.swift                    Standalone Swift script — generates icon PNGs
│
├── Sources/
│   ├── WikipediaScraperCore/          Library — shared by CLI, macOS app, and iPadOS app
│   │   ├── PersonModel.swift
│   │   ├── WikipediaClient.swift
│   │   ├── InfoboxParser.swift
│   │   ├── DateParser.swift
│   │   ├── GEDCOMBuilder.swift
│   │   ├── GEDZIPBuilder.swift
│   │   ├── MappingsReporter.swift
│   │   └── ScraperConfig.swift
│   │
│   ├── WikipediaScraperSharedUI/      SwiftUI library — shared by macOS + iPadOS apps
│   │   ├── EditableTypes.swift        Editable model wrappers (EditablePerson, etc.)
│   │   └── PersonEditorView.swift     PersonEditorView, EventSectionContent, MediaThumbnail
│   │
│   ├── WikipediaScraper/              CLI executable target
│   │   └── WikipediaScraperCommand.swift
│   │
│   ├── WikipediaScraperApp/           macOS SwiftUI app target
│   │   ├── WikipediaScraperApp.swift  @main, FocusedValues, menu bar commands
│   │   ├── ContentView.swift          URL bar, toolbar, window layout
│   │   ├── PersonViewModel.swift      ViewModel — fetch + NSSavePanel export
│   │   ├── Info.plist
│   │   └── Assets.xcassets/           macOS app icon (7 PNG sizes)
│   │
│   └── WikipediaScraperIPad/          iPadOS SwiftUI app target
│       ├── WikipediaScraperIPadApp.swift  @main (iOS) + macOS compilation stub
│       ├── iPadContentView.swift      Touch UI, .fileExporter modifiers
│       ├── iPadPersonViewModel.swift  ViewModel — fetch + FileDocument export
│       ├── Info.plist
│       └── Assets.xcassets/           iPad app icon (9 PNG sizes)
│
└── .build/                            SPM build artefacts (git-ignored)
```

**Package targets:**

| Target | Type | Platform | Dependencies |
|--------|------|----------|--------------|
| `WikipediaScraperCore` | Library | macOS 13, iOS 16 | ZIPFoundation |
| `WikipediaScraperSharedUI` | Library | macOS 13, iOS 16 | WikipediaScraperCore |
| `WikipediaScraper` | Executable | macOS 13 | WikipediaScraperCore, ArgumentParser |
| `WikipediaScraperApp` | Executable | macOS 13 | WikipediaScraperCore, WikipediaScraperSharedUI |
| `WikipediaScraperIPad` | Executable | iOS 16 | WikipediaScraperCore, WikipediaScraperSharedUI |

All public types in `WikipediaScraperCore` and `WikipediaScraperSharedUI` carry explicit `public` access modifiers so they are visible across module boundaries. All cross-module structs carry explicit `public init(...)` declarations because synthesised memberwise initialisers are `internal` by default in Swift.

---

## 2. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                      WikipediaScraperCore                        │
│                                                                  │
│  Wikipedia APIs ──► WikipediaClient                             │
│                          │                                       │
│                   wikitext + summary                             │
│                          │                                       │
│           ┌──────────────▼──────────────┐                       │
│           │       InfoboxParser          │                       │
│           │  (uses DateParser +          │                       │
│           │   ScraperConfig)             │                       │
│           └──────────────┬──────────────┘                       │
│                          │ PersonData                            │
│           ┌──────────────▼──────────────┐                       │
│           │      GEDCOMBuilder          │                       │
│           └──────────────┬──────────────┘                       │
│                          │ GEDCOM 7.0 text                       │
│           ┌──────────────▼──────────────┐                       │
│           │      GEDZIPBuilder          │ (optional)             │
│           └──────────────┬──────────────┘                       │
│                          │ .zip / .gdz archive                   │
└──────────────────────────┼───────────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────────┐
│           WikipediaScraperSharedUI                               │
│                          │                                       │
│         EditableTypes ◄──┤──► PersonEditorView                  │
│         (EditablePerson, │    (Form, MediaThumbnail,             │
│          EditableEvent,  │     EventSectionContent)              │
│          …)              │                                       │
└──────────────────────────┼───────────────────────────────────────┘
                           │
          ┌────────────────┼──────────────────┐
          │                │                  │
  WikipediaScraper   WikipediaScraperApp  WikipediaScraperIPad
  (CLI)              (macOS SwiftUI)      (iPadOS SwiftUI)
  AsyncParsable      PersonViewModel      iPadPersonViewModel
  Command            ContentView          iPadContentView
                     NSSavePanel          .fileExporter
```

All three consumers call the same `WikipediaClient`, `InfoboxParser`, `GEDCOMBuilder`, and `GEDZIPBuilder` APIs. The macOS and iPadOS apps share the `EditableTypes` and `PersonEditorView` from `WikipediaScraperSharedUI`; they differ only in their export mechanisms and window setup.

---

## 3. Core Library — WikipediaScraperCore

### 3.1 PersonModel

**File:** `Sources/WikipediaScraperCore/PersonModel.swift`

The central data model. All other modules either produce or consume these types.

#### Type hierarchy

```
PersonData
├── name: String?
├── givenName / surname / birthName / alternateNames
├── sex: Sex                        (.male | .female | .unknown)
│
├── birth / death / burial / baptism: PersonEvent?
│       ├── date: GEDCOMDate?
│       ├── place / note: String?
│       └── cause: String?          (death only)
│
├── titledPositions: [TitledPosition]
│       ├── title: String
│       ├── startDate / endDate: GEDCOMDate?
│       ├── place / note: String?
│       ├── predecessor / predecessorWikiTitle: String?
│       └── successor   / successorWikiTitle:   String?
│
├── customEvents: [CustomEvent]     (type, date, place, note)
├── personFacts:  [PersonFact]      (type, value)
├── honorifics:   [String]
│
├── spouses:  [SpouseInfo]          (name, wikiTitle, marriageDate, marriagePlace, divorceDate)
├── children: [PersonRef]           (name, wikiTitle)
├── father / mother: PersonRef?
├── parents: [PersonRef]
│
├── occupations: [String]
├── nationality / religion: String?
│
├── imageURL / imageFilePath: String?
├── imageData: Data?
├── imageMimeType: String?
├── additionalMedia: [AdditionalMedia]
│
└── wikiURL / wikiTitle / wikiExtract: String?
    wikiSections: [(title: String, text: String)]
```

#### GEDCOMDate

```swift
struct GEDCOMDate {
    var qualifier: Qualifier    // .exact | .about | .before | .after
    var day: Int?
    var month: Int?
    var year: Int?
    var original: String        // raw input preserved for diagnostics

    var gedcom: String          // serialises to "ABT 24 MAY 1819" etc.
    var isEmpty: Bool
}
```

The `gedcom` computed property emits the GEDCOM 7 date string: qualifier prefix (`ABT`, `BEF`, `AFT`) followed by optional day, month abbreviation, year.

---

### 3.2 WikipediaClient

**File:** `Sources/WikipediaScraperCore/WikipediaClient.swift`

All network I/O. Stateless — every method is `static async throws`.

#### APIs used

| Method | Endpoint |
|--------|----------|
| `fetchSummary` | `https://en.wikipedia.org/api/rest_v1/page/summary/{title}` |
| `fetchWikitext` | `https://en.wikipedia.org/w/api.php?action=parse&prop=wikitext` |
| `fetchSections` | REST summary + custom section splitter |
| `fetchAllImageURLs` | `action=query&prop=images` then `action=query&prop=imageinfo` (batched) |
| `fetchImageData` | Direct HTTPS GET to Wikimedia URL |

#### Image filtering (`fetchAllImageURLs`)

The method applies heuristics to avoid downloading decorative images:
- Skips files with names matching: `flag`, `coat`, `seal`, `logo`, `icon`, `blank`, `map`, `signature`, `ribbon`, `bar`, `star`, `cross`.
- Skips images smaller than 100×100 px (as reported by `imageinfo`).
- Skips non-raster MIME types (SVG, PDF, OGG, etc.).
- Deduplicates against the portrait URL.
- Processes `imageinfo` in batches of 20 titles per API request.

#### Error types

```swift
enum ScraperError: LocalizedError {
    case invalidURL(String)
    case httpError(Int, String)
    case parseError(String)
}
```

---

### 3.3 InfoboxParser

**File:** `Sources/WikipediaScraperCore/InfoboxParser.swift`

The most complex module. Converts raw wikitext into a `PersonData` value.

#### Entry point

```swift
InfoboxParser.parse(
    wikitext:  String,
    pageTitle: String,
    verbose:   Bool,
    config:    ScraperConfig = .empty
) -> (person: PersonData, rawFields: [String: String])
```

#### Pipeline

```
wikitext
   │
   ▼
extractInfoboxFields()       Find {{ Infobox … }} block via balanced brace scan;
   │                         split on | respecting nested {{ }} and [[ ]]
   │  [String: String]
   ▼
Field normalisation          Lowercase keys, underscore spaces, trim values
   │
   ▼
Template expansion           expandListTemplates() — {{hlist|a|b}} → "a, b"
   │                         expandUnbulleted(), {{plainlist|…}} → newlines
   ▼
Name fields                  name, given_name, surname → givenName, surname
   │                         birth_name, honorific_prefix/suffix → honorifics
   ▼
Sex                          gender / sex / pronouns keywords → Sex enum
   │
   ▼
Life event fields            birth_date, birth_place → PersonEvent via DateParser
   │                         death_date/place/cause, burial_place, baptism_date/place
   ▼
Royalty loop                 succession_N / reign_N / title_N / predecessor_N / successor_N
   │                         One TitledPosition per numbered group; predecessorWikiTitle
   │                         extracted before cleanText strips wikilinks
   ▼
Officeholder loop            office_N / term_start_N / term_end_N / preceded_by_N / succeeded_by_N
   │                         Same TitledPosition structure
   ▼
Custom events                coronation, other user-configured [events] fields
   │
   ▼
Facts                        house/dynasty, party, branch, rank, awards, battles, allegiance,
   │                         service_years, user-configured [facts] fields
   ▼
Family fields                spouse → SpouseInfo (handles {{marriage|name|date|place}} template)
   │                         children → [PersonRef], father/mother, parents
   ▼
Attributes                   occupation/profession → occupations
   │                         nationality/citizenship, religion/faith
   ▼
Image                        image → wikimediaThumbURL() → PersonData.imageURL
   │
   ▼
PersonData
```

#### Key helper: cleanText

```swift
cleanText(_ raw: String) -> String?
```

Strips: HTML tags, `<ref>…</ref>`, wikilinks `[[target|label]]` → `label`, templates `{{ }}`, HTML entities, and normalises whitespace. Returns `nil` for empty result. Applied to all displayable values before storing in PersonData.

#### Key helper: extractWikiTitle

```swift
extractWikiTitle(from raw: String) -> String?
```

Extracts the target of the first `[[target]]` or `[[target|label]]` wikilink without calling cleanText, preserving the raw article title. Used for predecessor/successor wiki title fields that need to survive cleanText.

---

### 3.4 DateParser

**File:** `Sources/WikipediaScraperCore/DateParser.swift`

Converts Wikipedia date strings and templates to `GEDCOMDate` values.

#### parse(_ raw: String) pipeline

```
raw string
   │
   ├─► wikitext template?  {{birth date|Y|M|D}}, {{death date|…}},
   │                       {{start date|…}}, {{circa|…}}, {{floruit|…}}
   │                       → GEDCOMDate with components
   │
   ├─► ISO date?           YYYY-MM-DD or YYYY-MM
   │                       → GEDCOMDate with components
   │
   └─► plain text          Strip templates, check qualifier prefixes
                           ("c.", "circa", "about", "abt", "bef", "aft", "after", "before")
                           Tokenise remaining text; match month names; assign
                           day/year by value range (1–31 = day, 1000–2100 = year)
                           → GEDCOMDate with qualifier
```

#### parseRange(_ raw: String) pipeline

```
raw string
   │
   ├─► {{reign|Y|M|D|Y|M|D}}  Two 6-arg templates → (start, end)
   │
   ├─► en-dash / em-dash       "1819–1901" → split and parse each half
   │
   └─► " to " separator        "1819 to 1901" → split and parse each half
```

---

### 3.5 GEDCOMBuilder

**File:** `Sources/WikipediaScraperCore/GEDCOMBuilder.swift`

Converts an array of `PersonData` values to a GEDCOM 7.0 text string.

#### Internal types

```swift
// Tracks all allocated IDs and cross-references for one build pass
struct BuildContext {
    let sourID: String          // @S1@
    let indiID: String          // @I1@ for the primary person
    var spouseIDs:    [(SpouseInfo,  String)]   // (spouse, @Iy@)
    var childIDs:     [(PersonRef,   String)]
    var fatherID:     (PersonRef,    String)?
    var motherID:     (PersonRef,    String)?
    var famIDs:       [(SpouseInfo,  String)]   // @Fz@ per marriage
    var parentFamID:  String?
    var assocLinks:   [AssocLink]
    var assocStubs:   [AssocStub]
    var objeID:       String?
    var addlObjeIDs:  [String]
}

struct AssocLink  { var targetID: String; var rela: String }
struct AssocStub  { var id: String; var name: String }
```

#### build(persons:verbose:) workflow

```
1. Pre-register all command-line persons in personRegistry [wikiTitle → xrefID]
   and familyRegistry [canonical key → famID].

2. For each person, create a BuildContext:
   - resolve() allocates new xref IDs for referenced people not yet in registry,
     or looks up existing IDs for people already registered (deduplication).
   - Registers all newly-allocated IDs back into personRegistry immediately,
     so subsequent BuildContexts find them.

3. Write HEAD block.

4. For each context:
   a. writeMainIndividual()    — full INDI record
   b. writeSpouseStubs()       — minimal INDI for unresolved spouses
   c. writeChildrenStubs()     — minimal INDI for unresolved children
   d. writeParentStubs()       — minimal INDI for unresolved father/mother
   e. writeAssocStubs()        — minimal INDI for predecessor/successor
   f. writeFamilies()          — FAM records (skips already-written families)

5. Write SOUR record for Wikipedia.

6. Write OBJE records for portraits and additional media.

7. Write TRLR.
```

#### buildPrimaryName

Detects honorific prefixes by checking if the Wikipedia article title ends with the constructed `"GivenName Surname"` core. If it does, the leading text becomes `NPFX`.

```
wikiTitle = "Queen Victoria"
given     = "Victoria"
surname   = ""
core      = "Victoria"
wikiTitle.hasSuffix("Victoria") → true
candidate = "Queen"  → npfx = "Queen"

Output:
  1 NAME Queen Victoria
  2 NPFX Queen
  2 GIVN Victoria
```

#### Line wrapping

```swift
func line(_ level: Int, _ content: String)
```

Splits content into UTF-8-aware chunks ≤ 255 bytes per GEDCOM line. Continuation lines use the `CONT` tag at `level + 1`.

---

### 3.6 GEDZIPBuilder

**File:** `Sources/WikipediaScraperCore/GEDZIPBuilder.swift`

Creates a GEDZIP-compliant ZIP archive per GEDCOM 7 §3.2.

```swift
GEDZIPBuilder.create(
    gedcom:     String,
    mediaFiles: [(path: String, data: Data)],
    at:         URL
) throws
```

Archive structure enforced:
- `gedcom.ged` is always at the ZIP root (required by spec).
- `FILE` tags in the GEDCOM text must contain relative paths matching the `path` component of each `mediaFiles` entry.
- GEDCOM text is deflate-compressed; media files are stored uncompressed (they are already compressed formats).

Error cases:
- `GEDZIPError.cannotCreateArchive(String)` — ZIPFoundation failure.
- `GEDZIPError.encodingFailed` — GEDCOM text couldn't be encoded as UTF-8.

---

### 3.7 MappingsReporter

**File:** `Sources/WikipediaScraperCore/MappingsReporter.swift`

Produces the `--mappings` diagnostic table. Driven entirely by introspecting the `PersonData` returned from `InfoboxParser.parse()` and correlating fields back to the `rawFields` dictionary.

```swift
MappingsReporter.report(
    person:    PersonData,
    rawFields: [String: String],
    wikiURL:   String?
) -> String
```

Output format: three-column table (Infobox Field | Raw Value | GEDCOM Output) followed by an Unmapped Fields section listing any raw fields not consumed by the parser.

---

### 3.8 ScraperConfig

**File:** `Sources/WikipediaScraperCore/ScraperConfig.swift`

Loads and exposes the `.wikipediascraperrc` configuration file.

```swift
struct ScraperConfig {
    var factMappings:  [String: String]   // infobox key → FACT TYPE label
    var eventMappings: [String: String]   // infobox key → EVEN TYPE label

    static let empty: ScraperConfig
    static func load(path: String?, verbose: Bool) -> ScraperConfig
}
```

The file uses a simple INI-like format: blank lines and `#`/`;`-prefixed lines are ignored; `[facts]` and `[events]` section headers switch the active mapping table; `key = value` lines populate the dictionaries.

---

## 4. Shared UI Library — WikipediaScraperSharedUI

**Directory:** `Sources/WikipediaScraperSharedUI/`

A SwiftUI library target that compiles for both macOS 13 and iOS 16. It contains everything shared between the macOS and iPadOS apps: the editable model layer and the main editor view hierarchy. Platform-specific colours are handled with `#if os(macOS)` / `#else` guards at the top of each file.

### 4.1 EditableTypes

**File:** `Sources/WikipediaScraperSharedUI/EditableTypes.swift`

The editable types mirror the `PersonModel` types but use plain `String` fields for every date, place, and name — matching SwiftUI's `TextField` binding requirement. All types are `public` with explicit `public init()` declarations.

```
EditablePerson
├── givenName / surname / birthName / sex
├── birth / death / burial / baptism : EditableEvent
│       └── date (String) / place / note / cause
├── titledPositions : [EditableTitledPosition]
│       └── title / startDate / endDate / place / predecessor / successor / note
├── customEvents : [EditableCustomEvent]
│       └── type (editable) / date / place / note
├── personFacts : [EditablePersonFact]
│       └── type (editable) / value
├── honorifics  : [String]
├── spouses     : [EditableSpouse]
│       └── name / marriageDate / marriagePlace / divorceDate
├── children    : [EditablePersonRef]
├── father / mother : String
├── occupations : [String]
├── nationality / religion : String
├── imageURL : String                       ← primary image URL
├── additionalMedia : [EditableMediaItem]
│       └── url (String) / caption (String)
└── wikiTitle / wikiURL / wikiExtract       ← read-only metadata
```

Each editable type provides:
- `init()` — blank instance for "Add" buttons.
- `init(from: PersonModelType)` — construct from parsed data.
- `toXxx() -> PersonModelType` — convert back for export; dates re-parsed via `DateParser.parse()`.

`EditablePerson.toPersonData()` assigns each property individually on a blank `PersonData()` (the memberwise init is `internal` in the Core module and not accessible here).

### 4.2 PersonEditorView

**File:** `Sources/WikipediaScraperSharedUI/PersonEditorView.swift`

`public struct PersonEditorView: View` — `Form { … }.formStyle(.grouped)`. All 14 sections are extracted to computed `@ViewBuilder` properties for readability. No business logic; entirely driven by `@Binding var person: EditablePerson`.

**Sections in order:**

| Section | Key controls |
|---------|-------------|
| Identity | `TextField` for names; `Picker(.segmented)` for sex |
| Media | `AsyncImage` thumbnails + URL `TextField`; add/remove additional media |
| Birth / Death / Burial / Baptism | `EventSectionContent` sub-view |
| Titled Positions | Expandable rows — all fields editable including type |
| Custom Events | Expandable rows — event type is a `TextField` |
| Facts | Two-column `TextField` rows — both type and value editable |
| Honorifics | Single `TextField` rows |
| Spouses | Expandable rows |
| Children | `TextField` list |
| Parents | `TextField` for father, mother |
| Occupations | `TextField` list |
| Other | `TextField` for nationality, religion |

**Supporting types (also public):**

`EventSectionContent` — reusable sub-view for any life event (date/place/note/cause fields). Used by all four life-event sections.

`MediaThumbnail` — `AsyncImage`-based thumbnail with all loading phases handled. Uses `NSColor`/`UIColor` conditionally for separator and background colours:

```swift
#if os(macOS)
import AppKit
private var separatorColor:   Color { Color(NSColor.separatorColor) }
private var thumbnailBGColor: Color { Color(NSColor.unemphasizedSelectedContentBackgroundColor) }
#else
import UIKit
private var separatorColor:   Color { Color(UIColor.separator) }
private var thumbnailBGColor: Color { Color(UIColor.secondarySystemBackground) }
#endif
```

---

## 5. CLI Tool — WikipediaScraper

### 5.1 Entry Point and Argument Parsing

**File:** `Sources/WikipediaScraper/WikipediaScraperCommand.swift`

Uses [swift-argument-parser](https://github.com/apple/swift-argument-parser) via the `AsyncParsableCommand` protocol.

```swift
@main
struct WikipediaScraper: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "WikipediaScraper",
        abstract: "Convert one or more Wikipedia person pages to a GEDCOM 7.0 genealogy file.",
        version: "1.4.0"
    )

    @Argument  var wikipediaURLs: [String]
    @Option    var output: String?
    @Option    var config: String?
    @Flag      var verbose: Bool
    @Flag      var preflight: Bool
    @Flag      var zip: Bool
    @Flag      var mappings: Bool
    @Flag      var notes: Bool
    @Flag      var allimages: Bool
    @Flag      var noPeople: Bool

    mutating func validate() throws { … }   // mutual-exclusion checks
    mutating func run() async throws { … }  // main workflow
}
```

`validate()` enforces:
- At least one URL required.
- `--preflight`, `--zip`, `--mappings` are mutually exclusive.
- `--allimages` implies `--zip`; incompatible with `--preflight` and `--mappings`.
- `--output` incompatible with `--preflight`.

### 5.2 CLI Data Flow

```
for each URL in wikipediaURLs:
    1. WikipediaClient.pageTitle(from: url)           → pageTitle
    2. WikipediaClient.fetchSummary(pageTitle:)        → WikipediaSummary (thumbnail, extract)
    3. WikipediaClient.fetchWikitext(pageTitle:)        → wikitext string
    4. InfoboxParser.parse(wikitext:pageTitle:config:)  → PersonData

    if --mappings:
        MappingsReporter.report() → print to stdout; continue next URL

    if --notes:
        WikipediaClient.fetchSections()  → PersonData.wikiSections

    if zip mode and portrait URL present:
        WikipediaClient.fetchImageData() → PersonData.imageData + imageMimeType

    if --allimages:
        WikipediaClient.fetchAllImageURLs() → [(title, url, mime)]
        for each: fetchImageData() → AdditionalMedia items

──────────────── all persons collected ────────────────────

if not --nopeople:
    Collect referenced wiki titles from spouses/children/parents/titledPositions
    for each not already in persons list:
        fetch summary + wikitext → PersonData (same pipeline, notes/images skipped)

if --nopeople:
    Strip from each person: spouses/children/parents/titledPositions references
    whose wikiTitle is not in the command-line persons set

──────────────── build output ──────────────────────────────

GEDCOMBuilder.build(persons:)  → gedcom: String

if --preflight:   print gedcom to stdout
if zip mode:      GEDZIPBuilder.create(gedcom:mediaFiles:at:)
else:             gedcom.write(to: outputURL)
```

### 5.3 Referenced-Person Expansion

When not running in `--nopeople` mode, the tool collects Wikipedia article titles from:
- `person.spouses[*].wikiTitle`
- `person.children[*].wikiTitle`
- `person.father?.wikiTitle`, `person.mother?.wikiTitle`
- `person.parents[*].wikiTitle`
- `person.titledPositions[*].predecessorWikiTitle`
- `person.titledPositions[*].successorWikiTitle`

Titles already present in the command-line persons list are skipped. Each new title is fetched with the same `fetchSummary` + `fetchWikitext` + `InfoboxParser.parse` pipeline. The fetch is one level deep — referenced persons' own family links are **not** followed.

### 5.4 Deduplication

`GEDCOMBuilder` maintains two shared registries across all `BuildContext` instances:

```swift
var personRegistry: [String: String]   // wikiTitle or name → @Ix@ xref ID
var familyRegistry: [String: String]   // canonical key     → @Fx@ xref ID
```

**Person deduplication:** Before any contexts are built, all command-line persons are pre-registered. The `resolve(wikiTitle:name:)` helper checks `personRegistry` before allocating a new ID. If found, the existing ID is reused — the same INDI record gets linked from multiple contexts.

**Family deduplication:** A canonical key `"\(husbandID):\(wifeID)"` (IDs sorted so `@I1@:@I3@` and `@I3@:@I1@` are the same) is checked against `familyRegistry` before writing a FAM record. If found, the existing `@Fx@` is referenced — preventing duplicate FAM records for a couple who appear in each other's infoboxes.

### 5.5 --nopeople Mode

When `--nopeople` is set, after all command-line persons are parsed, a pre-processing pass strips all family and position references pointing to persons **not** on the command line:

```swift
let knownTitles = Set(persons.compactMap { $0.wikiTitle })

for i in persons.indices {
    persons[i].spouses  = persons[i].spouses.filter  { knownTitles.contains($0.wikiTitle ?? "") }
    persons[i].children = persons[i].children.filter { knownTitles.contains($0.wikiTitle ?? "") }
    // ... father, mother, parents ...
    for j in persons[i].titledPositions.indices {
        if !knownTitles.contains(persons[i].titledPositions[j].predecessorWikiTitle ?? "") {
            persons[i].titledPositions[j].predecessor = nil
            persons[i].titledPositions[j].predecessorWikiTitle = nil
        }
        // ... successor ...
    }
}
```

This runs before `GEDCOMBuilder.build()`, so the builder never sees the stripped references and produces no stub INDI records for them.

---

## 6. macOS App — WikipediaScraperApp

### 6.1 Scene and Window Setup

**File:** `Sources/WikipediaScraperApp/WikipediaScraperApp.swift`

```swift
@main
struct WikipediaScraperApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack { ContentView() }
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 960, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
            AppCommands()
        }
    }
}
```

`NavigationStack` provides a window title bar that updates via `.navigationTitle()` and standard toolbar chrome.

`AppCommands` wires the active window's `PersonViewModel` into the macOS menu bar using SwiftUI's focused-value system:

```swift
// Published from ContentView:
.focusedValue(\.personViewModel, vm)

// Consumed in AppCommands:
@FocusedValue(\.personViewModel) private var vm: PersonViewModel?
```

This allows File > Export as GEDCOM… (⌘E) and File > Export as ZIP… (⌘⇧E) to operate on whichever window is currently focused.

### 6.2 App Data Flow

```
User pastes URL → ContentView.urlBar
        │
        ▼ vm.fetch() called
PersonViewModel.fetch()
        │
        ├─ WikipediaClient.pageTitle(from: urlString)
        ├─ WikipediaClient.fetchSummary()        ─────┐ concurrent
        ├─ WikipediaClient.fetchWikitext()        ────┘ async let
        │
        ├─ InfoboxParser.parse(wikitext:pageTitle:)
        │
        └─ EditablePerson(from: parsedPerson)
                │  merge summary title, extract, imageURL
                └─► vm.person = editable
                    vm.hasData = true
                           │
                           ▼
                 PersonEditorView renders
                 all fields as TextFields
                 with bindings to vm.person
                           │
                           ▼ user edits
                 vm.person mutated in place
                           │
                           ▼ File > Export
                 person.toPersonData()  →  PersonData
                 GEDCOMBuilder.build()  →  GEDCOM text
                           │
                 ┌─────────┴──────────┐
                 │ .ged               │ .zip
                 │ NSSavePanel        │ fetchImageData() × N
                 │ write to URL       │ GEDZIPBuilder.create()
```

### 6.3 PersonViewModel

**File:** `Sources/WikipediaScraperApp/PersonViewModel.swift`

`@MainActor final class PersonViewModel: ObservableObject`

The ViewModel holds the in-flight URL string, the parsed/edited person (as `EditablePerson` from `WikipediaScraperSharedUI`), loading/error/status state, and drives all network and file I/O. Export uses `NSSavePanel` for the native macOS save dialog.

#### saveAsZip workflow

```swift
func saveAsZip() async {
    // NSSavePanel (async continuation pattern)
    // ──────────────────────────────────────────
    // 1. Fetch primary image:
    //    WikipediaClient.fetchImageData(from: person.imageURL)
    //    → build relative path "media/<safeName>.<ext>"
    //    → personData.imageFilePath = relPath
    //    → mediaFiles.append((relPath, data))
    //
    // 2. For each EditableMediaItem in person.additionalMedia:
    //    WikipediaClient.fetchImageData(from: item.url)
    //    → build relative path from item.caption or index
    //    → resolvedExtras.append(AdditionalMedia(filePath: relPath, …))
    //    → mediaFiles.append((relPath, data))
    //    (on fetch failure: fall back to URL reference, no embedded data)
    //
    // 3. personData.additionalMedia = resolvedExtras
    // 4. GEDCOMBuilder.build(persons: [personData])
    // 5. GEDZIPBuilder.create(gedcom:mediaFiles:at:)
}
```

### 6.4 ContentView

**File:** `Sources/WikipediaScraperApp/ContentView.swift`

Thin layout shell. All business logic lives in `PersonViewModel`.

```
NavigationStack
└── ContentView
    ├── urlBar          (HStack with styled background, TextField, fetch button)
    ├── Divider
    ├── errorBanner?    (red HStack, dismiss button)
    └── mainContent     (ScrollView > PersonEditorView  | ProgressView  | emptyState)
        .toolbar { Export Menu (⌘E / ⌘⇧E) }
        .navigationTitle(vm.person.wikiTitle | "Wikipedia to GEDCOM")
        .focusedValue(\.personViewModel, vm)
```

The URL bar uses `NSColor.textBackgroundColor` fill and `NSColor.separatorColor` stroke to match native macOS text field appearance while incorporating the globe icon and fetch button into a single pill-shaped row.

### 6.5 Export Paths

#### Export as GEDCOM (.ged)

```
person.toPersonData()
    → GEDCOMBuilder.build(persons: [personData], verbose: false)
    → String.write(to: url, atomically: true, encoding: .utf8)
```

The plain GEDCOM preserves remote URLs in all `FILE` tags; no images are downloaded.

#### Export as ZIP

```
person.toPersonData()                   ← base PersonData with URL references
fetch each image URL → (Data, mimeType)
build relative media paths              "media/<safe>.<ext>"
personData.imageFilePath = relPath      ← overrides imageURL for FILE tag
GEDCOMBuilder.build(persons: [personData])   ← FILE tags now use relative paths
GEDZIPBuilder.create(gedcom:mediaFiles:at:)  ← packs gedcom.ged + media/*
```

---

## 7. iPadOS App — WikipediaScraperIPad

### 7.1 Scene Setup

**File:** `Sources/WikipediaScraperIPad/WikipediaScraperIPadApp.swift`

```swift
#if os(iOS)
@main
struct WikipediaScraperIPadApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                iPadContentView()
            }
        }
    }
}
#else
// macOS compilation stub
@main
struct WikipediaScraperIPadApp {
    static func main() {}
}
#endif
```

The `WindowGroup` enables multi-window support on iPadOS (Stage Manager on supported hardware). No `.commands {}` block is needed on iPadOS — there is no menu bar.

### 7.2 Platform Compilation Strategy

The iPad target is a standard SPM `.executableTarget`. Since `swift build` on macOS compiles **all** targets, the iPad source files would otherwise fail to compile (they reference `UIKit`, `UIActivityViewController`, etc., which are unavailable on macOS). The solution: every iPad-specific source file wraps its entire content in `#if os(iOS)`:

```swift
#if os(iOS)
import UIKit
// ... all platform-specific code ...
#endif
```

`WikipediaScraperIPadApp.swift` additionally provides a `#else` block with a macOS-compatible `@main` entry-point stub. This guarantees the `WikipediaScraperIPad` executable always has a valid entry point for linking, regardless of the build platform.

The `WikipediaScraperSharedUI` library compiles correctly on both platforms using `#if os(macOS)` / `#else` guards for any platform-specific APIs (currently limited to colour system types).

Build matrix summary:

| Command | macOS targets built | iPadOS target built |
|---------|--------------------|--------------------|
| `swift build` | Core, SharedUI, CLI, macOS app, iPad stub | Empty files (stub only) |
| `xcodebuild -scheme WikipediaScraperIPad -destination iOS` | — | Core, SharedUI, iPad app |

### 7.3 iPadPersonViewModel

**File:** `Sources/WikipediaScraperIPad/iPadPersonViewModel.swift`

`@MainActor final class iPadPersonViewModel: ObservableObject`

The fetch logic is identical to the macOS ViewModel. Export differs: rather than presenting `NSSavePanel`, the ViewModel builds a `FileDocument` value and sets a Boolean flag that triggers SwiftUI's `.fileExporter` modifier, which presents the iOS document picker.

#### FileDocument types

```swift
struct GEDCOMDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var content: String
    // init(content:), init(configuration:), fileWrapper(configuration:)
}

struct ZIPDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    var data: Data
    // init(data:), init(configuration:), fileWrapper(configuration:)
}
```

#### saveAsGED workflow

```swift
func saveAsGED() {
    let personData = person.toPersonData()
    var builder    = GEDCOMBuilder()
    gedDocument    = GEDCOMDocument(content: builder.build(persons: [personData], verbose: false))
    isExportingGED = true      // triggers .fileExporter in iPadContentView
}
```

#### saveAsZip workflow

```swift
func saveAsZip() async {
    // Same image fetch loop as macOS saveAsZip():
    //   fetch primary image, build relative paths, build resolvedExtras
    //
    // Write ZIP to a temp file URL:
    //   FileManager.default.temporaryDirectory.appendingPathComponent(…)
    //   GEDZIPBuilder.create(gedcom:mediaFiles:at: tempURL)
    //
    // Read back as Data:
    //   let rawData = try Data(contentsOf: tempURL)
    //   FileManager.default.removeItem(at: tempURL)
    //
    // Trigger export sheet:
    //   zipDocument  = ZIPDocument(data: rawData)
    //   isExportingZip = true
}
```

The ZIP must be round-tripped through a temp file because `GEDZIPBuilder` writes to a URL via ZIPFoundation (it does not produce in-memory `Data` directly).

### 7.4 iPadContentView

**File:** `Sources/WikipediaScraperIPad/iPadContentView.swift`

Structurally identical to the macOS `ContentView` but adapted for touch:

| macOS ContentView | iPadContentView |
|-------------------|-----------------|
| `NSColor.textBackgroundColor` URL bar background | Plain `HStack` with `roundedBorder` text field |
| `ProgressView().controlSize(.small)` | `ProgressView().controlSize(.regular)` |
| `TextField` with no keyboard attributes | `TextField` + `.keyboardType(.URL)` + `.textInputAutocapitalization(.never)` + `.autocorrectionDisabled()` |
| `.keyboardShortcut(.return, modifiers: .command)` on fetch button | No keyboard shortcut (no hardware keyboard assumed) |
| `NSSavePanel` triggered from ViewModel | `.fileExporter` modifiers on the view |
| Empty state: "press Return or ⌘↩" | Empty state: "tap Return" |

The two `.fileExporter` modifiers are applied directly to the root `VStack`:

```swift
.fileExporter(
    isPresented:    $vm.isExportingGED,
    document:        vm.gedDocument,
    contentType:     .plainText,
    defaultFilename: vm.exportFilename + ".ged"
) { vm.handleExportResult($0) }

.fileExporter(
    isPresented:    $vm.isExportingZip,
    document:        vm.zipDocument,
    contentType:     .zip,
    defaultFilename: vm.exportFilename + ".zip"
) { vm.handleExportResult($0) }
```

Both present the standard iOS document picker, allowing the user to save to Files, iCloud Drive, or any connected provider.

### 7.5 Export Paths

#### Export as GEDCOM (.ged)

```
vm.saveAsGED()
    person.toPersonData()
    GEDCOMBuilder.build() → GEDCOM string
    GEDCOMDocument(content: gedcom)
    isExportingGED = true
        │
        ▼ .fileExporter triggers
    iOS document picker → user picks destination
    GEDCOMDocument.fileWrapper() → FileWrapper(regularFileWithContents: Data(string))
    system writes file
```

#### Export as ZIP

```
vm.saveAsZip() async
    fetch all images → (Data, mimeType) × N
    build mediaFiles [(path, data)]
    GEDCOMBuilder.build() → GEDCOM string
    GEDZIPBuilder.create() → writes to temp URL
    Data(contentsOf: tempURL) → zipData
    ZIPDocument(data: zipData)
    isExportingZip = true
        │
        ▼ .fileExporter triggers
    iOS document picker → user picks destination
    ZIPDocument.fileWrapper() → FileWrapper(regularFileWithContents: zipData)
    system writes file
```

---

## 8. Key Algorithms

### 8.1 Infobox Extraction

The infobox lives somewhere inside the wikitext as `{{ Infobox royalty | … }}` or similar. Extracting it reliably requires a balanced-brace scan rather than regex, because field values can themselves contain nested templates.

```
State machine variables:
  depth = 0       (nesting level)
  start = nil     (position of opening {{ )
  buffer = ""     (collected content)

For each character:
  "{{" → depth++; if depth == 1: start = position
  "}}" → depth--; if depth == 0 and start != nil:
           candidate = buffer[start..<position]
           if candidate starts with "Infobox": found!
  else → buffer += character
```

Once the block is found, fields are extracted with the same technique: split on `|` pipes, but only at `depth == 0` (skipping pipes inside nested templates and wikilinks).

### 8.2 Date Parsing

The parser handles three broad categories of Wikipedia date representation:

**1. Wikitext templates** — detected by `{{` prefix:
```
{{birth date|1819|5|24}}            → 24 MAY 1819
{{birth date and age|1819|5|24}}    → 24 MAY 1819
{{circa|1066}}                      → ABT 1066
{{floruit|1200}}                    → ABT 1200
{{reign|1837|6|20|1901|1|22}}       → FROM 20 JUN 1837 TO 22 JAN 1901
```

**2. ISO dates** — detected by YYYY-MM-DD pattern:
```
1819-05-24   → 24 MAY 1819
1819-05      → MAY 1819
```

**3. Plain text** — all remaining input:
- Strip any residual templates
- Check for qualifier keywords at start: `c.`, `circa`, `about`, `abt` → `.about`; `before`, `bef` → `.before`; `after`, `aft` → `.after`
- Tokenise on spaces, commas, dots
- Match tokens against month-name table (January/Jan/JANUARY/1 → 1)
- Assign remaining numeric tokens: value 1–31 → day; value 1000–2100 → year

### 8.3 GEDCOM Name Construction

Every person gets one primary `NAME` record derived from the Wikipedia article title (the most authoritative, canonical identifier). Structured name components are attached as subrecords.

```
If given+surname forms a suffix of wikiTitle:
    npfx = text before "given surname" in wikiTitle
    → "Queen Victoria": npfx="Queen", GIVN=Victoria

Primary NAME value:
    If npfx non-empty  → use full wikiTitle (e.g. "Queen Victoria")
    Elif given+surname → "Given /Surname/" (GEDCOM surname-slash notation)
    Elif given only    → wikiTitle
    Else               → wikiTitle

Subrecords always written:
    2 NPFX <npfx>       (if prefix detected)
    2 GIVN <givenName>  (if present)
    2 SURN <surname>    (if present)

Additional NAME records:
    If infobox structured name ≠ primary NAME:
        1 NAME <given /surname/>
        (with GIVN/SURN subrecords)
    If birthName present:
        1 NAME <birthName>
        2 TYPE birth
    For each alternateName:
        1 NAME <name>
        2 TYPE aka
```

### 8.4 Xref Allocation and Deduplication

All record IDs (`@Ix@`, `@Fx@`, `@Sx@`, `@Ox@`) are allocated from monotonically-increasing integers tracked as `inout` parameters passed through every `BuildContext` initialiser. This ensures uniqueness across the entire output file regardless of how many persons or contexts are processed.

```swift
// Shared state, passed inout through every BuildContext.init
var personRegistry: [String: String]   // lookup: wikiTitle/name → @Ix@
var familyRegistry: [String: String]   // lookup: "husbID:wifeID" → @Fx@
var nextI: Int                         // next INDI counter
var nextF: Int                         // next FAM counter
var nextO: Int                         // next OBJE counter
```

The `resolve(wikiTitle:name:)` closure inside each `BuildContext.init`:
1. Checks `personRegistry[wikiTitle]` — returns existing ID if found.
2. Checks `personRegistry[name]` — returns existing ID if found.
3. Otherwise allocates `"@I\(nextI)@"`, increments `nextI`, writes both the wikiTitle and name into `personRegistry`, and returns the new ID as `known: false` (triggering stub generation).

Family deduplication uses a canonical key `sorted([husbandID, wifeID]).joined(separator: ":")`. Before writing any FAM record, `familyRegistry[key]` is checked; if present, the existing `@Fx@` is used and no new record is written.

---

## 9. GEDCOM 7.0 Output Reference

### Record structure

```
0 HEAD
1 GEDC
2 VERS 7.0
1 DATE <today>
2 TIME <HH:MM:SS>
1 SOUR WikipediaScraper
2 VERS 1.4.0

0 @I1@ INDI
1 NAME Queen Victoria
2 NPFX Queen
2 GIVN Victoria
1 NAME Victoria
2 GIVN Victoria
1 NAME Alexandrina Victoria
2 TYPE birth
1 SEX F
1 BIRT
2 DATE 24 MAY 1819
2 PLAC Kensington Palace, London, England
2 SOUR @S1@
3 PAGE https://en.wikipedia.org/wiki/Queen_Victoria
1 DEAT
2 DATE 22 JAN 1901
2 CAUS Old age
1 TITL The Queen
1 EVEN Queen of the United Kingdom
2 TYPE Nobility title
2 DATE FROM 20 JUN 1837 TO 22 JAN 1901
1 FACT Hanover
2 TYPE House
1 OCCU Monarch
1 NATI British
1 ASSO @I2@
2 RELA Predecessor
1 NOTE (article sections, one NOTE per section)
1 FAMS @F1@
1 FAMC @F2@
1 SOUR @S1@
2 PAGE https://en.wikipedia.org/wiki/Queen_Victoria
2 DATA
3 TEXT (first 500 chars of wikiExtract)
1 OBJE @O1@

0 @F1@ FAM
1 HUSB @I3@
1 WIFE @I1@
1 MARR
2 DATE 10 FEB 1840
2 PLAC Chapel Royal, St James's Palace, London
1 CHIL @I4@
1 SOUR @S1@

0 @S1@ SOUR
1 TITL Wikipedia
1 AUTH Wikipedia contributors
1 PUBL Wikimedia Foundation
1 WWW https://en.wikipedia.org/
1 DATE <today>

0 @O1@ OBJE
1 FILE media/Queen_Victoria.jpg
2 FORM image/jpeg
2 TITL Queen Victoria portrait

0 TRLR
```

### Line splitting

Lines exceeding 255 UTF-8 bytes are split:
```
1 NOTE This is a very long note that exceeds the limit …
2 CONT … continuation of the note
```
Splits occur at byte boundaries, never inside a multi-byte UTF-8 sequence.

---

## 10. Configuration System

`ScraperConfig` is loaded once at startup and passed through to `InfoboxParser.parse()`. Fields in the config override or supplement the built-in field mapping tables inside `InfoboxParser`.

**Processing order:**
1. Built-in field handling runs first (birth/death dates, royalty succession, officeholder, etc.).
2. After built-ins, `config.factMappings` is iterated: if the infobox contains a matching key and it hasn't been consumed by a built-in, a new `PersonFact` is appended.
3. Similarly for `config.eventMappings` → `CustomEvent`.
4. If a key already has a built-in mapping but also appears in the config, the config's display name **overrides** the built-in label (the GEDCOM TYPE value is replaced).

**Example override:**
```ini
[facts]
party = Political Party   # overrides default "Political party"
```

The case-sensitivity of infobox field keys is normalised to lowercase during extraction, so config keys should be lowercase.

---

## 11. Icon Generation

**File:** `make_icon.swift`

A standalone Swift script (not part of any build target) that generates app icons for both the macOS and iPadOS apps using CoreGraphics. Run from the project root:

```bash
swift make_icon.swift
# or via Makefile:
make icons
```

The script generates two sets of PNG files:

| Output directory | Sizes (px) | Target |
|-----------------|-----------|--------|
| `Sources/WikipediaScraperApp/Assets.xcassets/AppIcon.appiconset/` | 16, 32, 64, 128, 256, 512, 1024 | macOS |
| `Sources/WikipediaScraperIPad/Assets.xcassets/AppIcon.appiconset/` | 20, 29, 40, 58, 76, 80, 152, 167, 1024 | iPadOS |

The `make app` target calls `xcrun actool` to compile the macOS PNGs into `AppIcon.icns` and `Assets.car` inside the `.app` bundle. Xcode compiles the iPad icon catalog automatically when building the `WikipediaScraperIPad` scheme.

### Design

The icon renders in a CoreGraphics bitmap context (Y-axis flipped to top-left origin):

1. **Background** — radial gradient from rich forest green (`#1D4A35`) at the centre to near-black (`#0D2A1D`) at the edges.
2. **Decorative tree silhouette** — overlapping filled circles in a slightly lighter dark green, forming an organic canopy shape. A trunk rectangle descends to the bottom.
3. **Glow halo** — radial gradient centred on the subject node creates a warm gold ambient glow.
4. **Connecting lines** — round-capped lines in warm gold form the pedigree chart branches: trunk stub → subject → two parents → four grandparents.
5. **Node circles** — filled circles at each junction, increasing in brightness toward the subject (cream-gold at bottom, darker gold at top).
6. **Person silhouettes** — head circle + rounded-rectangle body in a dark forest colour, rendered inside every node.
7. **Subject rim** — a subtle white stroke ring around the subject node for visual prominence.
8. **Leaf accents** — two semi-transparent green bezier-path leaves in the upper corners.

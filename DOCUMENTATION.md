# WikipediaScraper — Technical Documentation

This document covers the software architecture, data-flow pipelines, and module internals for both the command-line tool and the macOS app. It is intended for developers working on or extending the codebase.

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
4. [CLI Tool — WikipediaScraper](#4-cli-tool--wikipediascraper)
   - [Entry Point and Argument Parsing](#41-entry-point-and-argument-parsing)
   - [CLI Data Flow](#42-cli-data-flow)
   - [Referenced-Person Expansion](#43-referenced-person-expansion)
   - [Deduplication](#44-deduplication)
   - [--nopeople Mode](#45---nopeople-mode)
5. [macOS App — WikipediaScraperApp](#5-macos-app--wikipediascraperapp)
   - [Scene and Window Setup](#51-scene-and-window-setup)
   - [App Data Flow](#52-app-data-flow)
   - [PersonViewModel](#53-personviewmodel)
   - [ContentView](#54-contentview)
   - [PersonEditorView](#55-personeditorview)
   - [Export Paths](#56-export-paths)
6. [Key Algorithms](#6-key-algorithms)
   - [Infobox Extraction](#61-infobox-extraction)
   - [Date Parsing](#62-date-parsing)
   - [GEDCOM Name Construction](#63-gedcom-name-construction)
   - [Xref Allocation and Deduplication](#64-xref-allocation-and-deduplication)
7. [GEDCOM 7.0 Output Reference](#7-gedcom-70-output-reference)
8. [Configuration System](#8-configuration-system)
9. [Icon Generation](#9-icon-generation)

---

## 1. Project Structure

```
WikipediaScraper/
├── Package.swift                      SPM manifest — three targets
├── Makefile                           Build, install, app-bundle, test targets
├── make_icon.swift                    Standalone Swift script — generates app icon PNGs
│
├── Sources/
│   ├── WikipediaScraperCore/          Library target — shared between CLI and app
│   │   ├── PersonModel.swift
│   │   ├── WikipediaClient.swift
│   │   ├── InfoboxParser.swift
│   │   ├── DateParser.swift
│   │   ├── GEDCOMBuilder.swift
│   │   ├── GEDZIPBuilder.swift
│   │   ├── MappingsReporter.swift
│   │   └── ScraperConfig.swift
│   │
│   ├── WikipediaScraper/              CLI executable target
│   │   └── WikipediaScraperCommand.swift
│   │
│   └── WikipediaScraperApp/          macOS SwiftUI app target
│       ├── WikipediaScraperApp.swift
│       ├── ContentView.swift
│       ├── PersonEditorView.swift
│       ├── PersonViewModel.swift
│       ├── Info.plist
│       └── Assets.xcassets/
│           └── AppIcon.appiconset/    7 PNG sizes + Contents.json
│
└── .build/                            SPM build artefacts (git-ignored)
```

**Package targets:**

| Target | Type | Dependencies |
|--------|------|--------------|
| `WikipediaScraperCore` | Library | ZIPFoundation |
| `WikipediaScraper` | Executable | WikipediaScraperCore, ArgumentParser |
| `WikipediaScraperApp` | Executable | WikipediaScraperCore |

All public types in `WikipediaScraperCore` carry explicit `public` access modifiers so they are visible to both executables. Struct synthesised memberwise initialisers are `internal` by default in Swift, so all structs used across the module boundary carry explicit `public init(...)` declarations.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    WikipediaScraperCore                     │
│                                                             │
│  Wikipedia APIs ──► WikipediaClient                        │
│                          │                                  │
│                   wikitext + summary                        │
│                          │                                  │
│           ┌──────────────▼──────────────┐                  │
│           │       InfoboxParser          │                  │
│           │  (uses DateParser +          │                  │
│           │   ScraperConfig)             │                  │
│           └──────────────┬──────────────┘                  │
│                          │ PersonData                       │
│           ┌──────────────▼──────────────┐                  │
│           │      GEDCOMBuilder          │                  │
│           └──────────────┬──────────────┘                  │
│                          │ GEDCOM 7.0 text                  │
│           ┌──────────────▼──────────────┐                  │
│           │      GEDZIPBuilder          │ (optional)        │
│           └──────────────┬──────────────┘                  │
│                          │ .zip / .gdz archive              │
└──────────────────────────┼──────────────────────────────────┘
                           │
          ┌────────────────┴────────────────┐
          │                                 │
    WikipediaScraper                 WikipediaScraperApp
    (CLI — ArgumentParser)           (macOS SwiftUI app)
    WikipediaScraperCommand          PersonViewModel
                                     ContentView
                                     PersonEditorView
```

Both consumers call the same `WikipediaClient`, `InfoboxParser`, `GEDCOMBuilder`, and `GEDZIPBuilder` APIs. The only difference is the orchestration layer: the CLI uses `AsyncParsableCommand`, the app uses `@MainActor ObservableObject`.

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

The `gedcom` computed property emits the GEDCOM 7 date string: qualifier prefix (`ABT`, `BEF`, `AFT`) followed by optional day, month abbreviation, year. An exact date with no components returns `""`.

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
    wikitext: String,
    pageTitle: String,
    verbose: Bool,
    config: ScraperConfig = .empty
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

## 4. CLI Tool — WikipediaScraper

### 4.1 Entry Point and Argument Parsing

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

### 4.2 CLI Data Flow

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

### 4.3 Referenced-Person Expansion

When not running in `--nopeople` mode, the tool collects Wikipedia article titles from:
- `person.spouses[*].wikiTitle`
- `person.children[*].wikiTitle`
- `person.father?.wikiTitle`, `person.mother?.wikiTitle`
- `person.parents[*].wikiTitle`
- `person.titledPositions[*].predecessorWikiTitle`
- `person.titledPositions[*].successorWikiTitle`

Titles already present in the command-line persons list are skipped. Each new title is fetched with the same `fetchSummary` + `fetchWikitext` + `InfoboxParser.parse` pipeline. The fetch is one level deep — referenced persons' own family links are **not** followed.

### 4.4 Deduplication

`GEDCOMBuilder` maintains two shared registries across all `BuildContext` instances:

```swift
var personRegistry: [String: String]   // wikiTitle or name → @Ix@ xref ID
var familyRegistry: [String: String]   // canonical key     → @Fx@ xref ID
```

**Person deduplication:** Before any contexts are built, all command-line persons are pre-registered. The `resolve(wikiTitle:name:)` helper checks `personRegistry` before allocating a new ID. If found, the existing ID is reused — the same INDI record gets linked from multiple contexts.

**Family deduplication:** A canonical key `"\(husbandID):\(wifeID)"` (IDs sorted so `@I1@:@I3@` and `@I3@:@I1@` are the same) is checked against `familyRegistry` before writing a FAM record. If found, the existing `@Fx@` is referenced — preventing duplicate FAM records for a couple who appear in each other's infoboxes.

### 4.5 --nopeople Mode

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

## 5. macOS App — WikipediaScraperApp

### 5.1 Scene and Window Setup

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

`NavigationStack` provides:
- A window title bar that updates via `.navigationTitle()` inside `ContentView`.
- Standard macOS toolbar chrome for `.toolbar { }` items.

`AppCommands` wires the active window's `PersonViewModel` into the macOS menu bar using SwiftUI's focused-value system:

```swift
// Published from ContentView:
.focusedValue(\.personViewModel, vm)

// Consumed in AppCommands:
@FocusedValue(\.personViewModel) private var vm: PersonViewModel?
```

This allows File > Export as GEDCOM… and File > Export as ZIP… to operate on whichever window is currently focused.

### 5.2 App Data Flow

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
                 │ write to URL       │ fetchImageData() × N
                 │                   │ GEDZIPBuilder.create()
```

### 5.3 PersonViewModel

**File:** `Sources/WikipediaScraperApp/PersonViewModel.swift`

`@MainActor final class PersonViewModel: ObservableObject`

The ViewModel is the single source of truth for the app window. It holds the in-flight URL string, the parsed/edited person, loading/error/status state, and drives all network and file I/O.

#### Editable model hierarchy

The editable types mirror the PersonModel types but use plain `String` fields for every date, place, and name — matching SwiftUI's `TextField` binding requirement.

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
├── children    : [EditablePersonRef]
├── father / mother : String
├── occupations : [String]
├── nationality / religion : String
├── imageURL : String                   ← primary image URL
├── additionalMedia : [EditableMediaItem]
│       └── url (String) / caption (String)
└── wikiTitle / wikiURL / wikiExtract   ← read-only metadata
```

Each editable type provides:
- `init()` — blank instance for "Add" buttons.
- `init(from: PersonModelType)` — construct from parsed data.
- `toXxx() -> PersonModelType` — convert back for export, parsing dates via `DateParser.parse()`.

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

### 5.4 ContentView

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

### 5.5 PersonEditorView

**File:** `Sources/WikipediaScraperApp/PersonEditorView.swift`

`Form { … }.formStyle(.grouped)` — macOS grouped form style rendering. All 14 sections are extracted to computed `@ViewBuilder` properties for readability. No business logic; entirely driven by `@Binding var person: EditablePerson`.

**Sections in order:**

| Section | Key controls |
|---------|-------------|
| Identity | `TextField` for names; `Picker(.segmented)` for sex |
| Media | `AsyncImage` thumbnails + URL `TextField`; Add/remove additional media |
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

`MediaThumbnail` is a private sub-view that uses `AsyncImage` with a fallback placeholder icon. Each additional-media item displays a live thumbnail that updates as the URL field changes.

### 5.6 Export Paths

#### Export as GEDCOM (.ged)

```
person.toPersonData()
    → GEDCOMBuilder.build(persons: [personData], verbose: false)
    → String.write(to: url, atomically: true, encoding: .utf8)
```

The plain GEDCOM uses remote URLs for all `FILE` tags (no embedded media). `personData.imageURL` is preserved as-is in the OBJE record.

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

## 6. Key Algorithms

### 6.1 Infobox Extraction

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

### 6.2 Date Parsing

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

### 6.3 GEDCOM Name Construction

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

### 6.4 Xref Allocation and Deduplication

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

## 7. GEDCOM 7.0 Output Reference

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

## 8. Configuration System

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

## 9. Icon Generation

**File:** `make_icon.swift`

A standalone Swift script (not part of any build target) that generates the app icon programmatically using CoreGraphics. Run from the project root:

```bash
swift make_icon.swift
```

This overwrites all PNG files in `Sources/WikipediaScraperApp/Assets.xcassets/AppIcon.appiconset/` and regenerates icons at 16, 32, 64, 128, 256, 512, and 1024 pixels. The `make app` target then calls `xcrun actool` to compile these PNGs into `AppIcon.icns` and `Assets.car` inside the `.app` bundle.

### Design

The icon renders in a 1024×1024 CoreGraphics bitmap context (Y-axis flipped to top-left origin):

1. **Background** — radial gradient from rich forest green (`#1D4A35`) at the centre to near-black (`#0D2A1D`) at the edges.
2. **Decorative tree silhouette** — overlapping filled circles in a slightly lighter dark green, forming an organic canopy shape behind the chart. A trunk rectangle descends from the canopy to the bottom.
3. **Glow halo** — radial gradient centred on the subject node creates a warm gold ambient glow.
4. **Connecting lines** — round-capped lines in warm gold (`rgba(0.80, 0.60, 0.25, 0.80)`) form the pedigree chart branches: trunk stub → subject → two parents → four grandparents.
5. **Node circles** — filled circles at each junction, increasing in brightness toward the subject (cream-gold at bottom, darker gold at top).
6. **Person silhouettes** — head circle + rounded-rectangle body in a dark forest colour, rendered inside every node.
7. **Subject rim** — a subtle white stroke ring around the subject node to make it visually prominent.
8. **Leaf accents** — two semi-transparent green bezier-path leaves in the upper corners.

The 7 output sizes share identical drawing code; the `size` parameter scales all coordinates proportionally, ensuring the icon looks sharp at every resolution including Retina @2x slots.

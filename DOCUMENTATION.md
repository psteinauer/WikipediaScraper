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
   - [FetchOptionsView](#43-fetchoptionsview)
   - [LLMSettings](#44-llmsettings)
   - [SourceInfo and SourceDetailView](#45-sourceinfo-and-sourcedetailview)
   - [AIProgressSheet](#46-aiprogresssheet)
   - [GEDCOMPreviewSheet](#47-gedcompreviewsheet)
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
   - [LLMSettingsView](#66-llmsettingsview)
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
│   │   ├── PersonEditorView.swift     Card-based editor: EditorSection, SubGroup, FieldRow,
│   │   │                              EventSectionContent, MediaThumbnail, image cells
│   │   ├── FetchOptionsView.swift     Fetch-option toggles (Notes, All Images, Main Person Only,
│   │   │                              AI Analysis + API key); macOS=card, iOS=chip strip
│   │   ├── LLMSettings.swift          Shared singleton (ObservableObject) persisting AI toggle
│   │   │                              and Anthropic API key to UserDefaults
│   │   ├── SourceInfo.swift           SourceInfo struct — Wikipedia / Claude AI source metadata
│   │   ├── SourceDetailView.swift     Detail view for a selected SourceInfo
│   │   ├── URLListBar.swift           Reusable URL chip bar (iPad)
│   │   ├── AIProgressSheet.swift      Sheet showing per-article AI analysis progress
│   │   └── GEDCOMPreviewSheet.swift   Sheet with syntax-highlighted GEDCOM preview + copy/save
│   │
│   ├── WikipediaScraper/              CLI executable target
│   │   └── WikipediaScraperCommand.swift
│   │
│   ├── WikipediaScraperApp/           macOS SwiftUI app target
│   │   ├── WikipediaScraperApp.swift  @main, FocusedValues, menu bar commands
│   │   ├── ContentView.swift          URL chip bar, NavigationSplitView, sidebar, detail
│   │   ├── PersonViewModel.swift      ViewModel — multi-person fetch, NSSavePanel export,
│   │   │                              MacFamilyTree integration, GEDCOM preview
│   │   ├── LLMSettingsView.swift      macOS Settings popover — AI toggle + API key
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
│  EditableTypes ◄─────────┤──► PersonEditorView                  │
│  (EditablePerson, …)     │    (EditorSection cards, SubGroup,    │
│                          │     FieldRow, MediaThumbnail)         │
│  LLMSettings.shared      │──► FetchOptionsView                  │
│  (ObservableObject)      │    SourceInfo / SourceDetailView      │
│  LLMClient               │    AIProgressSheet                    │
│                          │    GEDCOMPreviewSheet                 │
└──────────────────────────┼───────────────────────────────────────┘
                           │
          ┌────────────────┼──────────────────┐
          │                │                  │
  WikipediaScraper   WikipediaScraperApp  WikipediaScraperIPad
  (CLI)              (macOS SwiftUI)      (iPadOS SwiftUI)
  AsyncParsable      PersonViewModel      iPadPersonViewModel
  Command            ContentView          iPadContentView
                     NSSavePanel          .fileExporter
                     LLMSettingsView
```

All three consumers call the same `WikipediaClient`, `InfoboxParser`, `GEDCOMBuilder`, and `GEDZIPBuilder` APIs. The macOS and iPadOS apps share `EditableTypes`, `PersonEditorView`, `FetchOptionsView`, `LLMSettings`, and the AI/preview sheet components from `WikipediaScraperSharedUI`; they differ only in their export mechanisms, window setup, and settings UI.

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

A SwiftUI library target that compiles for both macOS 13 and iOS 16. It contains everything shared between the macOS and iPadOS apps: the editable model layer, the main editor view hierarchy, fetch-option controls, AI analysis infrastructure, GEDCOM preview, and source metadata. Platform-specific colours and layouts are handled with `#if os(macOS)` / `#else` guards.

### 4.1 EditableTypes

**File:** `Sources/WikipediaScraperSharedUI/EditableTypes.swift`

The editable types mirror the `PersonModel` types but use plain `String` fields for every date, place, and name — matching SwiftUI's `TextField` binding requirement. All types are `public` with explicit `public init()` declarations.

```
EditablePerson
├── id: UUID                            ← stable identity for List selection
├── isStub: Bool                        ← true for referenced-person stubs
├── givenName / surname / birthName / sex
├── birth / death / burial / baptism : EditableEvent
│       └── date (String) / place / note / cause
├── titledPositions : [EditableTitledPosition]
│       └── title / startDate / endDate / place / predecessor / successor / note
├── customEvents : [EditableCustomEvent]
│       └── id: UUID / type / date / place / note
├── personFacts : [EditablePersonFact]
│       └── id: UUID / type / value
├── honorifics  : [String]
├── spouses     : [EditableSpouse]
│       └── name / marriageDate / marriagePlace / divorceDate
├── children    : [EditablePersonRef]
│       └── id: UUID / name
├── father / mother : String
├── occupations : [String]
├── nationality / religion : String
├── imageURL : String                       ← primary image URL
├── additionalMedia : [EditableMediaItem]
│       └── id: UUID / url (String) / caption (String)
│
├── LLM-enriched fields (populated by LLMClient.analyze — displayed inline
│   in blue within their respective sections; fully editable and deletable)
│   ├── llmAlternateNames : [String]
│   ├── llmTitles         : [String]
│   ├── llmFacts          : [EditablePersonFact]
│   │       └── id: UUID / type / value
│   ├── llmEvents         : [EditableCustomEvent]
│   │       └── id: UUID / type / date / place / note
│   └── influentialPeople : [EditableInfluentialPerson]
│           └── id: UUID / name / wikiTitle / relationship / note
│
└── wikiTitle / wikiURL / wikiExtract / wikiSections   ← metadata (read-only)
```

Each editable type provides:
- `init()` — blank instance for "Add" buttons.
- `init(from: PersonModelType)` — construct from parsed data.
- `toXxx() -> PersonModelType` — convert back for export; dates re-parsed via `DateParser.parse()`.

`EditablePerson.toPersonData()` assigns each property individually on a blank `PersonData()` (the memberwise init is `internal` in the Core module and not accessible here).

`EditableInfluentialPerson` is the editable counterpart of `InfluentialPerson`. `PersonViewModel` maps LLM analysis results to these Editable types on assignment so the view can bind to them immediately.

### 4.2 PersonEditorView

**File:** `Sources/WikipediaScraperSharedUI/PersonEditorView.swift`

`public struct PersonEditorView: View` — a `ScrollView` containing a vertical stack of collapsible `EditorSection` cards. No business logic; entirely driven by `@Binding var person: EditablePerson`.

#### Card-based layout

The editor replaces the earlier `Form { … }.formStyle(.grouped)` approach with custom card components:

| Component | Role |
|-----------|------|
| `EditorSection` | Top-level collapsible card — SF Symbol icon + bold title header with disclosure chevron; content inside a rounded rectangle with shadow and 0.5 pt border |
| `SubGroup` | Second-level collapsible group inside a section — smaller chevron header, content indented 18 pt |
| `FieldRow` | Two-column field row — right-aligned label at 120 pt, content fills the remainder; optional inset divider |
| `EventSectionContent` | Reusable Date/Place/Note/Cause field set for life events |

`EditorSection` stores `Content` directly (not as a closure):
```swift
private struct EditorSection<Content: View>: View {
    init(_ title: String, systemImage: String,
         isExpanded: Binding<Bool>,
         @ViewBuilder content: () -> Content) {
        self.content = content()   // evaluated once in init
        …
    }
}
```
This avoids the Swift compile error about storing a non-escaping `@ViewBuilder` closure.

#### Sections in order

The eight top-level sections correspond to the keys in `PersonEditorView.topLevelSections` and are rendered in this order:

| Section key | SF Symbol | Sub-sections / Contents |
|-------------|-----------|------------------------|
| `"Name and Gender"` | `person.text.rectangle` | Wikipedia title (read-only), given name, surname, sex picker; primary image shown to the right when the image URL is set |
| `"Events"` | `calendar.badge.clock` | Sub-groups: Birth, Death, Burial, Baptism (`EventSectionContent`), Spouses, Titled Positions, Custom Events. `llmEvents` (AI-generated) appear at the end of the Custom Events sub-group in **blue text**, editable and deletable. |
| `"Facts"` | `list.bullet` | Sub-groups: Honorifics & Titles, Custom Facts, Occupations, Attributes (nationality/religion). `llmTitles` appear at the end of Honorifics, `llmFacts` at the end of Custom Facts — both in **blue text**. |
| `"Additional Names"` | `person.badge.plus` | Birth name text field. `llmAlternateNames` appear below birth name as individual editable rows in **blue text**. |
| `"Media"` | `photo` | Thumbnail grid — primary image cell (star badge, popover), additional media cells (caption overlay); Add Image button |
| `"Notes"` | `doc.text` | Read-only display of `wikiSections` (Wikipedia article sections, populated with Notes enabled). Hidden when empty. |
| `"Sources"` | `doc.badge.gearshape` | Wikipedia article link + "Claude AI (Anthropic)" row when `hasLLMData` is true |
| `"Other"` | `ellipsis.circle` | Sub-groups: Parents (father/mother), Children. `influentialPeople` (AI-generated) appear after the Children sub-group in **blue text** with name, relationship, and note fields. |

LLM-enriched items in every section use identical `FieldRow` / `TextField` layout to standard items. They are distinguished solely by `.foregroundStyle(.blue)` on the text field content. All have a Remove button that mutates the corresponding `llmXxx` or `influentialPeople` array on `EditablePerson`.

#### Expand / collapse behaviour

Expand/collapse state is tracked in `@State private var expandedSections: Set<String>`, initialised to `["Name and Gender"]` so only that section is open by default.

The `isExpanded(for:)` binding setter implements three modifier-key behaviours (macOS only):

| Modifier | Behaviour |
|----------|-----------|
| None | Toggle just this section |
| ⌥ Option | Toggle this section **and all its sub-sections** |
| ⌘⌥ Cmd+Option | Toggle **all other top-level sections** (without changing their sub-section states) |

Sub-section keys follow the pattern `"SectionName.SubName"` (e.g. `"Events.Birth"`). The static dictionary `PersonEditorView.subSections` maps each top-level key to its sub-section key list.

#### Primary image beside Name and Gender

When `person.imageURL` is non-empty and `"Name and Gender"` is expanded, `MediaThumbnail(urlString:height:)` (fit-to-height mode) is placed in an `HStack` to the right of the name card. The card height is measured once via an `overlay { GeometryReader }` on first appearance and stored in `@State private var nameCardHeight: CGFloat = 160`.

#### MediaThumbnail

`public struct MediaThumbnail: View` — custom async image loader backed by a shared `NSCache` / `NSImage` (macOS) or `UIImage` (iOS) cache. Two initialisers:

```swift
// Fixed rect — fills the given width×height (crops if needed)
init(urlString: String, width: CGFloat = 72, height: CGFloat = 90)

// Fit-to-height — preserves image aspect ratio at the given height
init(urlString: String, height: CGFloat)
```

Loading phases: `.idle` → `.loading` → `.success(Image)` | `.failure`. Cancelled tasks (when the person changes mid-load) reset to `.idle` so the task re-runs cleanly on re-navigation.

### 4.3 FetchOptionsView

**File:** `Sources/WikipediaScraperSharedUI/FetchOptionsView.swift`

`public struct FetchOptionsView: View` — compact option strip providing four toggles:

| Toggle | Binding | Effect |
|--------|---------|--------|
| AI Analysis | `LLMSettings.shared.isEnabled` | Run Claude AI enrichment after fetch |
| Notes | `$useNotes` | Include Wikipedia article sections as GEDCOM notes |
| All Images | `$useAllImages` | Download all article images into ZIP export |
| Main Person Only | `$noPeople` | Strip family stubs from the output |

**macOS:** Renders as a rounded card (`NSColor.windowBackgroundColor` background, 10 pt corner radius, 0.5 pt border, drop shadow) with a "Fetch Options" header, a divider, and a vertical list of `Toggle(.checkbox)` controls. When AI Analysis is enabled, an API key `SecureField` appears below the toggles.

**iPadOS:** Renders as a horizontally-scrollable row of `Toggle(.button).buttonBorderShape(.capsule)` chips. The API key field appears below the row when AI Analysis is enabled.

### 4.4 LLMSettings

**File:** `Sources/WikipediaScraperSharedUI/LLMSettings.swift`

```swift
public final class LLMSettings: ObservableObject {
    public static let shared = LLMSettings()
    @Published public var isEnabled: Bool   // UserDefaults key: "llm_enabled"
    @Published public var apiKey:    String // UserDefaults key: "anthropic_api_key"
}
```

Singleton accessed via `LLMSettings.shared`. Changes persist to `UserDefaults` immediately via `didSet`. Used by `FetchOptionsView`, `LLMSettingsView`, and `PersonViewModel`.

### 4.5 SourceInfo and SourceDetailView

**Files:** `Sources/WikipediaScraperSharedUI/SourceInfo.swift`, `SourceDetailView.swift`

`SourceInfo` is a plain value type representing one data source:

```swift
public struct SourceInfo: Identifiable {
    public enum SourceType { case wikipedia, claudeAI }
    public let id: UUID          // stable well-known IDs for wikipedia and claudeAI
    public let type: SourceType
    public let name: String
    public let icon: String      // SF Symbol name
    public let description: String
    public let citedByNames: [String]  // wikiTitle strings of persons citing this source
}
```

Two well-known IDs are defined as constants (`SourceInfo.wikipediaID`, `SourceInfo.claudeAIID`). `PersonViewModel.sources` computes the active source list by inspecting the current `persons` array.

`SourceDetailView` renders the description text, cited-by list, and a link to the source website in a read-only detail panel.

### 4.6 AIProgressSheet

**File:** `Sources/WikipediaScraperSharedUI/AIProgressSheet.swift`

A `.sheet` presented while AI analysis is running. Displays one row per article with a progress spinner (or checkmark/X when complete) and an expandable list of streaming step messages received from `LLMClient.analyze(onProgress:)`.

```swift
public struct AIProgressEntry: Identifiable {
    public var id: UUID
    public var title:   String        // Wikipedia article title
    public var steps:   [String]      // incremental messages from the LLM
    public var isDone:  Bool
    public var failed:  Bool
}
```

### 4.7 GEDCOMPreviewSheet

**File:** `Sources/WikipediaScraperSharedUI/GEDCOMPreviewSheet.swift`

A `.sheet` with a scrollable, monospaced display of the generated GEDCOM text. Provides toolbar buttons to copy the text to the clipboard and to save it to a file (via `NSSavePanel` on macOS or a share sheet on iPadOS). The sheet is triggered by `vm.showingGEDCOMPreview = true` after export or via the "View GEDCOM…" menu item.

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
            ContentView()
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 740)
        .commands {
            CommandGroup(replacing: .newItem) {}
            AppCommands()
        }
    }
}
```

`AppCommands` wires the active window's `PersonViewModel` into the macOS menu bar using SwiftUI's focused-value system:

```swift
// Published from ContentView:
.focusedValue(\.personViewModel, vm)

// Consumed in AppCommands:
@FocusedValue(\.personViewModel) private var vm: PersonViewModel?
```

This allows File > Export as GEDCOM… and File > Export as ZIP… to operate on whichever window is currently focused.

### 6.2 App Data Flow

```
User clicks + in URL chip bar → AddURLSheet → vm.addURL()
        │
        ▼ ⌘↩ or fetch button pressed → vm.fetch()
PersonViewModel.fetch()   (loops over all URLs)
        │
        for each URL:
        ├─ WikipediaClient.pageTitle(from: url)
        ├─ WikipediaClient.fetchSummary()   ─────┐ concurrent async let
        ├─ WikipediaClient.fetchWikitext()  ─────┘
        │
        ├─ InfoboxParser.parse(wikitext:pageTitle:)
        ├─ EditablePerson(from: parsedPerson)
        │    + merge summary.title, extract, imageURL
        │
        ├─ (if useNotes)     WikipediaClient.fetchSections()
        ├─ (if useAllImages) WikipediaClient.fetchAllImageURLs()
        │
        └─ (if LLMSettings.shared.isEnabled)
              LLMClient.analyze(pageTitle:wikitext:extract:apiKey:onProgress:)
              → [PersonFact] / [CustomEvent] / [InfluentialPerson] mapped to Editable types
              → editable.llmAlternateNames / llmTitles / llmFacts / llmEvents / influentialPeople
              → AIProgressSheet streams live messages
              → items appear inline in blue within their respective editor sections
        │
        ├─ upsert into vm.persons (replace stub/existing by wikiTitle, else append)
        └─ vm.selectedPersonID = editable.id
                │
                ▼
    rebuildStubs() — adds minimal EditablePerson stubs for referenced family members
                │
                ▼ ContentView detail column shows PersonEditorView
    person fields editable as TextFields via @Binding
                │
                ▼ Export button / File menu
    persons.filter(!isStub).map(toPersonData())
    GEDCOMBuilder.build(persons:)  →  GEDCOM text
                │
        ┌───────┴──────────────┬──────────────────┐
        │ .ged                 │ .zip / MFT        │ preview
        │ NSSavePanel          │ fetch images      │ GEDCOMPreviewSheet
        │ write to URL         │ GEDZIPBuilder     │ (no file I/O)
                               │ [open in MFT 11]
```

### 6.3 PersonViewModel

**File:** `Sources/WikipediaScraperApp/PersonViewModel.swift`

`@MainActor final class PersonViewModel: ObservableObject`

#### Published properties

| Property | Type | Description |
|----------|------|-------------|
| `urls` | `[String]` | Wikipedia article URLs — persisted to `UserDefaults("url_list")` |
| `persons` | `[EditablePerson]` | All fetched persons plus stubs; drives the sidebar list |
| `selectedPersonID` | `UUID?` | Currently selected person in the sidebar |
| `isLoading` | `Bool` | True while any URL is being fetched |
| `errorMessage` | `String?` | Shown in the sidebar error banner |
| `statusMessage` | `String?` | Shown in the toolbar while loading |
| `mediaWarnings` | `[String]` | Per-image download failure messages; shown in an alert |
| `aiProgressEntries` | `[AIProgressEntry]` | Streamed AI analysis steps per article |
| `showingAIProgress` | `Bool` | Triggers `AIProgressSheet` |
| `gedcomPreviewText` | `String?` | GEDCOM text for the preview sheet |
| `showingGEDCOMPreview` | `Bool` | Triggers `GEDCOMPreviewSheet` |
| `useNotes` | `Bool` | Persisted fetch option |
| `useAllImages` | `Bool` | Persisted fetch option |
| `noPeople` | `Bool` | Persisted fetch option; changing triggers `rebuildStubs()` |

#### Key computed / derived state

```swift
var hasData: Bool { persons.contains { !$0.isStub } }

var sources: [SourceInfo] { … }
// Computes SourceInfo.wikipedia (if any non-stub has wikiURL/wikiTitle)
// and SourceInfo.claudeAI (if any non-stub has llm* or influentialPeople).

func selectedPersonBinding() -> Binding<EditablePerson>?
// Returns a live Binding into persons[id] for the selected person.
```

#### `rebuildStubs()`

Called after every fetch and whenever `noPeople` changes. When `noPeople == false`, extracts all referenced names (spouses, children, father, mother, titledPositions predecessors/successors, and `influentialPeople.wikiTitle`) from full (non-stub) persons and creates minimal `EditablePerson` stubs for any not already present in `persons`. When `noPeople == true`, removes all stubs. Note: `influentialPeople` is now `[EditableInfluentialPerson]`, so `wikiTitle` is a plain `String` (not `String?`).

#### Export workflows

**`saveAsGED()`** — `NSSavePanel` → `persons.filter(!isStub).map(toPersonData())` → `GEDCOMBuilder.build()` → `String.write(to:)`. After saving, sets `gedcomPreviewText` and opens `GEDCOMPreviewSheet`.

**`saveAsZip()` / `openInMacFamilyTree()`** — both delegate to `buildAndWriteZip(to:)`:

```
for each non-stub person:
    fetch primaryImage → "media/<title>.<ext>"
    for each additionalMedia item: fetch → "media/<title>_N.<ext>"
    (failures appended to mediaWarnings)

GEDCOMBuilder.build(persons: personDatas)
GEDZIPBuilder.create(gedcom:mediaFiles:at:)
```

`openInMacFamilyTree()` writes to a `FileManager.temporaryDirectory` URL then launches MacFamilyTree 11 via `/usr/bin/open -a "MacFamilyTree 11.app" <tempURL>`.

**`previewGEDCOM()`** — builds GEDCOM without saving; sets `gedcomPreviewText` and opens preview sheet.

### 6.4 ContentView

**File:** `Sources/WikipediaScraperApp/ContentView.swift`

Thin layout shell — all business logic lives in `PersonViewModel`.

```
ContentView (VStack)
├── urlBar  (ChipFlowLayout — wrapping chip row of URL chips + add button)
├── Divider
└── NavigationSplitView
    ├── sidebar (sidebarContent)
    │   ├── FetchOptionsView card
    │   ├── Divider
    │   ├── errorBanner? (red, dismissible)
    │   ├── Segmented picker: People | Sources
    │   ├── Divider
    │   └── peopleList (List vm.persons, selection vm.selectedPersonID)
    │       or sourcesList (List vm.sources, selection selectedSourceID)
    │
    └── detail (detailContent)
        People tab:   PersonEditorView(person: vm.selectedPersonBinding())
                      or emptyPeopleState
        Sources tab:  SourceDetailView(source:)
                      or emptySourceState
```

The **URL chip bar** uses `ChipFlowLayout` — a custom `Layout` that places chips left-to-right, wrapping to new rows when the available width is exceeded. The last item is always the "+" add button. Each `URLChip` shows the domain name of the URL and has an × button to remove it.

The **toolbar** provides:
- Leading: Settings button (gear / wand icon) → `LLMSettingsView` popover
- Centre: Fetch button (or progress spinner + status text while loading) — `⌘↩`
- Trailing: Export menu

**Export menu items:**
- Export as GEDCOM… → `vm.saveAsGED()`
- Export as ZIP… → `vm.saveAsZip()`
- Open in MacFamilyTree 11 → `vm.openInMacFamilyTree()`
- View GEDCOM… → `vm.previewGEDCOM()`

Disabled when `!vm.hasData`.

Two `.sheet` modifiers are attached to the root view: one for `GEDCOMPreviewSheet` and one for `AIProgressSheet`.

### 6.5 Export Paths

#### Export as GEDCOM (.ged)

```
persons.filter(!isStub).map(toPersonData())
    → GEDCOMBuilder.build(persons:, verbose: false)
    → String.write(to: url, atomically: true, encoding: .utf8)
    → opens GEDCOMPreviewSheet
```

The plain GEDCOM preserves remote URLs in all `FILE` tags; no images are downloaded.

#### Export as ZIP

```
for each non-stub person:
    fetch primaryImage            → "media/<title>.jpg/png/…"
    fetch each additionalMedia    → "media/<title>_N.jpg/…"
personData.imageFilePath = relPath    ← overrides imageURL for FILE tag
GEDCOMBuilder.build(persons: personDatas)   ← FILE tags use relative paths
GEDZIPBuilder.create(gedcom:mediaFiles:at:) ← packs gedcom.ged + media/*
```

### 6.6 LLMSettingsView

**File:** `Sources/WikipediaScraperApp/LLMSettingsView.swift`

A `Form { … }.formStyle(.grouped)` view presented in a popover from the toolbar settings button. Contains a single section ("Claude AI (Anthropic)") with:
- `Toggle("Enable AI Analysis")` bound to `LLMSettings.shared.isEnabled`
- `SecureField("sk-ant-…")` for the API key (shown only when enabled)
- A footer warning when the key is empty

Takes no init parameters — reads and writes `LLMSettings.shared` directly.

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

Structurally parallel to the macOS `ContentView` but adapted for touch:

| macOS ContentView | iPadContentView |
|-------------------|-----------------|
| Wrapping `ChipFlowLayout` URL chip bar | `URLListBar` (horizontal scrolling chip strip) |
| `FetchOptionsView` as a sidebar card | `FetchOptionsView` inline above the main content (chip strip mode) |
| `NavigationSplitView` with sidebar + detail | `NavigationStack` with `PersonEditorView` pushed |
| `NSSavePanel` triggered from ViewModel | `.fileExporter` modifiers on the view |
| Settings in toolbar popover (`LLMSettingsView`) | Settings as a `.sheet` |
| Empty state: "⌘↩ to fetch" | Empty state: "tap Fetch" |
| `ProgressView().controlSize(.small)` | `ProgressView().controlSize(.regular)` |

The two `.fileExporter` modifiers are applied to the root `VStack`:

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

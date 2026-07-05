# Part 2 Architecture And Design

## Objective

Part 2 delivers a metadata dependency analyzer for Salesforce fields. The solution lets a user:

- select an object
- select one or more fields on that object
- choose dependency categories
- run an analysis and view where those fields are referenced across metadata

The design favors a guided UI, category-based execution, and provider separation so the solution can evolve without turning the controller into a single large block of logic.

## High-Level Architecture

The implementation is split into three layers:

1. Presentation layer
   - LWC: `objectFieldSelector`
   - Responsible for object/field selection, category toggles, loading state, and grouped result rendering

2. Orchestration layer
   - Apex controller: `ObjectMetadataController`
   - Apex service: `FieldUsageAnalyzerService`
   - Responsible for input validation, field normalization, provider selection, and response shaping

3. Dependency provider layer
   - `ToolingDependencyUsageProvider`
   - `ReportUsageProvider`
   - `WorkflowUsageProvider`
   - `ReportTypeMetadataClient`
   - `ToolingApiRestClient`
   - Responsible for category-specific metadata retrieval and dependency extraction

## Main Design Decisions

### 1. Server-driven category registry

Dependency categories are defined in `FieldUsageAnalyzerService` and exposed to the UI through `getCategoryDefinitions()`.

Why this helps:

- the LWC does not hardcode the supported category list
- default vs optional categories can be controlled centrally
- the architecture stays open for adding new categories later

### 2. Provider-based execution model

Each dependency family is handled by a dedicated provider implementing `IMetadataUsageProvider`.

Why this helps:

- category logic stays isolated
- different metadata sources can be used per category
- failures can be contained per category instead of failing the full analysis

This is the key architectural choice in Part 2. It keeps the analyzer modular and much easier to reason about than a single monolithic metadata scanner.

### 3. Query-first, fallback-only-when-needed approach

For categories where `MetadataComponentDependency` is reliable, the analyzer uses Tooling API query results first.

This applies to the current query-first path for:

- Apex
- Flow
- Validation Rule
- Custom Field
- Layout
- Email Template

For FlexiPages, a dedicated metadata scan path exists because dependency query coverage is less reliable there.

Why this helps:

- fast categories stay efficient
- deeper scans are limited to places where they are actually needed
- the design avoids unnecessary metadata traversal for every category

### 4. Canonical field normalization in the service layer

The analyzer normalizes incoming field API names in `FieldUsageAnalyzerService` before provider execution.

Why this helps:

- protects the backend from client casing differences
- keeps provider matching logic simpler
- ensures result grouping is aligned to a single effective field key

### 5. Partial-success response model

`FieldUsageAnalyzerService.AnalysisResponse` returns:

- `resultsByCategory`
- `categoryErrors`
- normalized `fieldApiNames`

Why this helps:

- one failing metadata source does not blank the full screen
- the UI can show successful categories and failed categories together
- operational issues are easier to diagnose

## Execution Flow

### Object and field load

1. LWC calls `ObjectMetadataController.getAllObjects()`
2. Apex filters to accessible, queryable objects and removes noisy system variants like history/share/feed/change event objects
3. User selects an object
4. LWC calls `ObjectMetadataController.getFieldsForObject()`
5. Apex returns accessible fields for that object

### Dependency analysis

1. LWC calls `ObjectMetadataController.analyzeFieldUsage()`
2. Controller delegates to `FieldUsageAnalyzerService`
3. Service validates inputs
4. Service canonicalizes selected field API names
5. Service builds the provider registry
6. Each selected category runs through its provider
7. Results are aggregated into a single response
8. LWC groups the response by field, then by category, and renders the accordion/card output

## Category Handling Summary

### Tooling dependency categories

Handled by `ToolingDependencyUsageProvider`.

Primary pattern:

- resolve selected fields to metadata component ids
- query `MetadataComponentDependency`
- filter by allowed component types for the category
- dedupe and emit standardized usage rows

### FlexiPages

Also handled by `ToolingDependencyUsageProvider`, but through a metadata traversal fallback.

Primary pattern:

- list candidate FlexiPages
- load FlexiPage metadata
- recursively scan nested metadata structures for object and field references

### Reports

Handled by `ReportUsageProvider`.

Primary pattern:

- describe accessible reports
- serialize report metadata
- search for qualified field references in the report metadata payload

### Report Types

Handled by `ReportUsageProvider` with `ReportTypeMetadataClient`.

Primary pattern:

- use Metadata API SOAP calls to list report types
- read report type metadata in batches
- parse sections and column references
- match target object + field combinations

### Workflow / Process Builder

Handled by `WorkflowUsageProvider`.

Primary pattern:

- query workflow rules and field updates
- parse workflow metadata structures
- detect both criteria usage and field update usage

## API Usage Model

Part 2 uses both REST and SOAP, but for different metadata retrieval needs.

### REST usage

REST is used for Tooling API driven dependency analysis through `ToolingApiRestClient`.

This supports the query-first path for categories where Salesforce metadata dependencies can be retrieved efficiently from Tooling API, such as:

- Apex
- Flow
- Validation Rule
- Custom Field
- Layout
- Email Template
- FlexiPage inventory/detail retrieval
- Workflow metadata record retrieval

At a high level, REST is used where the platform exposes metadata records or dependency rows in a queryable way.

### SOAP usage

SOAP is used in `ReportTypeMetadataClient` to call the Metadata API for `ReportType` analysis.

This path is used because report type column exposure is metadata-structure driven and is better retrieved from Metadata API operations than from the standard dependency-query path.

At a high level, SOAP is used for:

- listing report type metadata full names
- reading report type metadata in batches
- parsing report type sections and field references

### Why both are present

The split is intentional:

- REST is the faster and simpler fit for queryable Tooling metadata and dependency graphs
- SOAP is used only where Metadata API is the better source of truth, specifically for report type structure

This keeps the implementation practical while still using the most appropriate Salesforce API for each metadata family.

## UI Design Summary

The LWC is intentionally not just a raw form plus flat list. The output is grouped to improve scanability when multiple fields and categories are analyzed together.

Current UX patterns:

- object picker
- field dual-list selection
- category checkboxes with default/optional behavior
- dynamic progress messaging during analysis
- grouped results by field
- nested category cards within each field section
- category-level error display

This is a good tradeoff for the assignment because it keeps the UI simple to use while still being structured enough for broader metadata scans.

## Performance Considerations

### Strengths in the current design

- category-based execution avoids scanning everything every time
- fast categories use query-first dependency retrieval
- report type retrieval batches metadata reads
- provider isolation helps keep logic focused and avoids redundant cross-category work
- results are deduped before returning to the client

### Expected heavier paths

- FlexiPage metadata traversal
- report metadata serialization and scanning
- workflow metadata analysis

These are correctly treated as deeper scans and are architecturally separated from the faster dependency-query categories.

## Error Handling Strategy

The design intentionally tolerates category-specific failures.

Examples:

- a Tooling API issue can fail one category while others still render
- a report type metadata failure can be surfaced without hiding report results

This is the right behavior for an analysis tool. Users get partial value instead of an all-or-nothing failure.

## Extensibility

The easiest extension path is to add a new provider and register a new category definition.

Future enahncements could include the metadata families that are currently using heuristic scanning rather than a guaranteed dependency graph.

The current provider registry pattern supports this without requiring a redesign.

## Current Limitations

At a high level, the current implementation still has a few natural limits:

- report scanning is limited to accessible reports and currently bounded queries
- some metadata families still require heuristic scanning rather than a guaranteed dependency graph
- FlexiPage and workflow scanning are more expensive than dependency-query categories
- there is no caching layer yet for repeated analysis of the same object/field set
- the SOAP calls are heavy and time consuming - introducing a caching layer or maybe maintinaing a dependency graph in the system would help for scaling as in a real org - the report dependencies are much higher and the current solution might not sustain without an Async job.


## Conclusion

Part 2 is built as a modular metadata analysis service with a lightweight UI, a controller/service orchestration layer, and category-specific providers behind a shared contract.

From an architecture perspective, the strongest parts of the design are:

- provider isolation
- server-driven category configuration
- query-first dependency retrieval
- category-level failure isolation
- UI grouping that makes multi-field results readable

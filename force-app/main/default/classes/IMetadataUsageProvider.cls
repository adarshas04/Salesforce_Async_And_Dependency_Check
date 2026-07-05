/**
 * IMetadataUsageProvider
 * ------------------------
 * Abstraction over "where is this field used" lookups for a single
 * dependency category (Apex, Flow, Layout, Report, Workflow, etc.).
 *
 * Each concrete provider implements one category so:
 *  - New categories can be added without touching the orchestrator.
 *  - Callout-based providers (Tooling API) can be mocked cleanly in tests
 *    via HttpCalloutMock, without needing live org metadata.
 */
public interface IMetadataUsageProvider {

    /**
     * @param objectApiName  API name of the object the field(s) belong to.
     * @param fieldApiNames  API names of the fields being analyzed.
     * @return List of UsageResult records found for this category.
     */
    List<FieldUsageAnalyzerService.UsageResult> findUsages(
        String objectApiName,
        List<String> fieldApiNames
    );

    /**
     * Machine-readable key for this category, matching the values sent
     * from the LWC's category checklist (e.g. 'APEX', 'REPORT').
     */
    String getCategoryKey();
}

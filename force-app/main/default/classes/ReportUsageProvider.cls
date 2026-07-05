/**
 * ReportUsageProvider
 * ----------------------
 * OPTIONAL-tier provider for reporting metadata.
 *
 * In this org, Tooling SOAP doesn't support the Report / CustomReportType
 * sObjects, so report usage falls back to:
 *   1. native Apex SOQL on the Report sObject to discover accessible report ids
 *   2. Reports.ReportManager.describeReport(...) for per-report metadata
 *   3. scanning only the actual reportMetadata payload for object/field references
 *
 * Report Type analysis intentionally uses only ReportType metadata. Inferring
 * report-type dependencies from report describe payloads is too noisy because
 * describeReport includes fields that are merely available through the report
 * type, not necessarily used by a saved report.
 */
public with sharing class ReportUsageProvider implements IMetadataUsageProvider {
    @TestVisible
    private static List<ReportDescriptor> testReportDescriptors;
    @TestVisible
    private static List<ReportTypeMetadataClient.ReportTypeRecord> testReportTypeRecords;
    @TestVisible
    private static String testReportTypeFailureMessage;

    private final String categoryKey;

    public ReportUsageProvider() {
        this('REPORT');
    }

    public ReportUsageProvider(String categoryKey) {
        this.categoryKey = categoryKey;
    }

    public String getCategoryKey() {
        return categoryKey;
    }

    public List<FieldUsageAnalyzerService.UsageResult> findUsages(
        String objectApiName,
        List<String> fieldApiNames
    ) {
        if (categoryKey == 'REPORT_TYPE') {
            return findReportTypeUsages(objectApiName, fieldApiNames);
        }
        return findReportUsages(objectApiName, fieldApiNames);
    }

    private List<FieldUsageAnalyzerService.UsageResult> findReportTypeUsages(
        String objectApiName,
        List<String> fieldApiNames
    ) {
        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        Set<String> dedupeKeys = new Set<String>();
        try {
            for (ReportTypeMetadataClient.ReportTypeRecord record : describeReportTypes()) {
                for (ReportTypeMetadataClient.ColumnReference columnReference : record.columnReferences) {
                    if (!equalsIgnoreCase(columnReference.tableName, objectApiName)) {
                        continue;
                    }

                    for (String fieldApiName : fieldApiNames) {
                        if (!equalsIgnoreCase(columnReference.fieldName, fieldApiName)) {
                            continue;
                        }

                        String reportTypeName = String.isBlank(record.label) ? record.fullName : record.label;
                        String dedupeKey = 'ReportType:' + reportTypeName + ':' + fieldApiName;
                        if (dedupeKeys.contains(dedupeKey)) {
                            continue;
                        }
                        dedupeKeys.add(dedupeKey);

                        results.add(new FieldUsageAnalyzerService.UsageResult(
                            'ReportType',
                            reportTypeName,
                            'Field exposed in report type metadata',
                            fieldApiName
                        ));
                    }
                }
            }
        } catch (Exception ex) {
            if (!isRecoverableReportTypeMetadataFailure(ex)) {
                throw ex;
            }
        }

        return results;
    }

    private List<FieldUsageAnalyzerService.UsageResult> findReportUsages(
        String objectApiName,
        List<String> fieldApiNames
    ) {
        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        Set<String> dedupeKeys = new Set<String>();
        for (ReportDescriptor descriptor : describeAccessibleReports()) {
            collectMatches(
                results,
                dedupeKeys,
                descriptor.reportName,
                'Report',
                'Field referenced in report metadata',
                descriptor.metadataJson,
                objectApiName,
                fieldApiNames
            );
        }
        return results;
    }

    private static void collectMatches(
        List<FieldUsageAnalyzerService.UsageResult> results,
        Set<String> dedupeKeys,
        String componentName,
        String componentType,
        String context,
        String metadataJson,
        String objectApiName,
        List<String> fieldApiNames
    ) {
        if (String.isBlank(componentName) || String.isBlank(metadataJson)) {
            return;
        }

        for (String fieldApiName : fieldApiNames) {
            if (!containsQualifiedFieldReference(metadataJson, objectApiName, fieldApiName)) {
                continue;
            }

            String dedupeKey = componentType + ':' + componentName + ':' + fieldApiName;
            if (dedupeKeys.contains(dedupeKey)) {
                continue;
            }
            dedupeKeys.add(dedupeKey);

            results.add(new FieldUsageAnalyzerService.UsageResult(
                componentType,
                componentName,
                context,
                fieldApiName
            ));
        }
    }

    @TestVisible
    private static Boolean containsQualifiedFieldReference(
        String metadataJson,
        String objectApiName,
        String fieldApiName
    ) {
        if (String.isBlank(metadataJson) || String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return false;
        }

        String lowerMetadata = metadataJson.toLowerCase();
        String lowerObjectName = objectApiName.toLowerCase();
        String lowerFieldName = fieldApiName.toLowerCase();
        if (lowerMetadata.contains('"' + lowerObjectName + '.' + lowerFieldName + '"') ||
            lowerMetadata.contains('\'' + lowerObjectName + '.' + lowerFieldName + '\'') ||
            lowerMetadata.contains(lowerObjectName + '.' + lowerFieldName)) {
            return true;
        }

        Integer tableIndex = lowerMetadata.indexOf('"table":"' + lowerObjectName + '"');
        while (tableIndex >= 0) {
            Integer fieldIndex = lowerMetadata.indexOf('"field":"' + lowerFieldName + '"', tableIndex);
            if (fieldIndex > tableIndex && fieldIndex - tableIndex <= 200) {
                return true;
            }
            tableIndex = lowerMetadata.indexOf('"table":"' + lowerObjectName + '"', tableIndex + 1);
        }

        return false;
    }

    private static List<ReportDescriptor> describeAccessibleReports() {
        if (Test.isRunningTest() && testReportDescriptors != null) {
            return testReportDescriptors;
        }

        List<ReportDescriptor> descriptors = new List<ReportDescriptor>();
        for (Report reportRow : [
            SELECT Id, Name, DeveloperName, FolderName
            FROM Report
            ORDER BY LastModifiedDate DESC
            LIMIT 200
        ]) {
            try {
                Reports.ReportDescribeResult describeResult = Reports.ReportManager.describeReport(reportRow.Id);
                String metadataJson = JSON.serialize(describeResult.getReportMetadata());
                String reportName = String.isBlank(reportRow.Name) ? reportRow.DeveloperName : reportRow.Name;
                descriptors.add(new ReportDescriptor(reportName, metadataJson));
            } catch (Exception ex) {
                // Skip reports the running user cannot describe.
                continue;
            }
        }
        return descriptors;
    }

    private static List<ReportTypeMetadataClient.ReportTypeRecord> describeReportTypes() {
        if (Test.isRunningTest() && testReportTypeRecords != null) {
            return testReportTypeRecords;
        }
        if (Test.isRunningTest() && testReportTypeFailureMessage != null) {
            throw new FieldUsageAnalyzerService.ProviderExecutionException(testReportTypeFailureMessage);
        }
        return ReportTypeMetadataClient.listReportTypes();
    }

    @TestVisible
    private static Boolean isRecoverableReportTypeMetadataFailure(Exception ex) {
        if (ex == null || String.isBlank(ex.getMessage())) {
            return false;
        }

        String message = ex.getMessage().toLowerCase();
        return message.contains('invalid_session_id') ||
            message.contains('not valid for use with the api');
    }

    private static Boolean equalsIgnoreCase(String left, String right) {
        return !String.isBlank(left) &&
            !String.isBlank(right) &&
            left.toLowerCase() == right.toLowerCase();
    }

    @TestVisible
    public class ReportDescriptor {
        public String reportName;
        public String metadataJson;

        public ReportDescriptor(String reportName, String metadataJson) {
            this.reportName = reportName;
            this.metadataJson = metadataJson;
        }
    }
}

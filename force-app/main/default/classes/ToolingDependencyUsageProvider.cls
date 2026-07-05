/**
 * ToolingDependencyUsageProvider
 * ---------------------------------
 * Handles dependency categories by:
 *   - querying Tooling API MetadataComponentDependency for categories that
 *     Salesforce exposes directly there (Apex, Flow, Validation Rules, Custom
 *     Field formulas/defaults, Layouts, Email Templates), then
 *   - using a targeted fallback only for categories that need a separate
 *     metadata scan path (currently FlexiPages).
 *
 * NOTE: MetadataComponentDependency requires Tooling API access and is
 * only available in orgs where dependency API is enabled.
 */
public with sharing class ToolingDependencyUsageProvider implements IMetadataUsageProvider {

    private static final Set<String> QUERY_FIRST_CATEGORIES = new Set<String>{
        'APEX', 'FLOW', 'VALIDATION_RULE', 'CUSTOM_FIELD', 'LAYOUT', 'EMAIL_TEMPLATE'
    };
    @TestVisible private static List<Map<String, Object>> testFlexiPageRows;
    @TestVisible private static Map<String, Map<String, Object>> testFlexiPageDetailsById;

    // Maps our category keys to the RefMetadataComponentType values
    // returned by MetadataComponentDependency.
    private static final Map<String, Set<String>> CATEGORY_TO_COMPONENT_TYPES = new Map<String, Set<String>>{
        'APEX' => new Set<String>{ 'ApexClass', 'ApexTrigger' },
        'FLOW' => new Set<String>{ 'Flow' },
        'VALIDATION_RULE' => new Set<String>{ 'ValidationRule' },
        'CUSTOM_FIELD' => new Set<String>{ 'CustomField' },
        'LAYOUT' => new Set<String>{ 'Layout' },
        'FLEXIPAGE' => new Set<String>{ 'FlexiPage' },
        'EMAIL_TEMPLATE' => new Set<String>{ 'EmailTemplate' },
        'WORKFLOW_PROCESS' => new Set<String>{ 'WorkflowRule', 'Flow' } // Process Builder persists as Flow metadata type
    };

    private final String categoryKey;

    public ToolingDependencyUsageProvider() {
        this('APEX');
    }

    public ToolingDependencyUsageProvider(String categoryKey) {
        this.categoryKey = categoryKey;
    }

    // getCategoryKey() is only meaningful for single-category providers;
    // this provider answers for several, so the registry in
    // FieldUsageAnalyzerService registers it explicitly under each key.
    public String getCategoryKey() {
        return categoryKey;
    }

    public List<FieldUsageAnalyzerService.UsageResult> findUsages(
        String objectApiName,
        List<String> fieldApiNames
    ) {
        Set<String> allowedComponentTypes = CATEGORY_TO_COMPONENT_TYPES.get(categoryKey);
        if (allowedComponentTypes == null || allowedComponentTypes.isEmpty() || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return new List<FieldUsageAnalyzerService.UsageResult>();
        }

        Map<String, String> fieldApiNameByComponentId = resolveFieldComponentIds(objectApiName, fieldApiNames);
        if (fieldApiNameByComponentId.isEmpty()) {
            return new List<FieldUsageAnalyzerService.UsageResult>();
        }

        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        Set<String> dedupeKeys = new Set<String>();
        if (QUERY_FIRST_CATEGORIES.contains(categoryKey)) {
            List<Object> records;
            try {
                records = ToolingApiRestClient.query(buildDependencyQuery(fieldApiNameByComponentId.keySet()));
            } catch (ToolingApiRestClient.ToolingApiException ex) {
                throw new FieldUsageAnalyzerService.ProviderExecutionException(
                    'Dependency lookup failed. ' + ex.getMessage()
                );
            }

            if (records != null) {
                results.addAll(buildDependencyResults(
                    records,
                    fieldApiNameByComponentId,
                    allowedComponentTypes,
                    dedupeKeys
                ));
            }
        }

        if (results.isEmpty() && categoryKey == 'FLEXIPAGE') {
            results.addAll(findFlexiPageUsages(
                objectApiName,
                fieldApiNames,
                dedupeKeys
            ));
        }

        return results;
    }

    @TestVisible
    private List<FieldUsageAnalyzerService.UsageResult> buildDependencyResults(
        List<Object> records,
        Map<String, String> fieldApiNameByComponentId,
        Set<String> allowedComponentTypes,
        Set<String> dedupeKeys
    ) {
        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        if (records == null || fieldApiNameByComponentId == null || fieldApiNameByComponentId.isEmpty()) {
            return results;
        }

        for (Object recObj : records) {
            Map<String, Object> rec = (Map<String, Object>) recObj;
            String refComponentId = normalizeMetadataComponentId((String) rec.get('RefMetadataComponentId'));
            String refComponentType = (String) rec.get('RefMetadataComponentType');
            String metadataComponentName = (String) rec.get('MetadataComponentName');
            String metadataComponentType = (String) rec.get('MetadataComponentType');

            if (refComponentType != 'CustomField' || !fieldApiNameByComponentId.containsKey(refComponentId)) {
                continue;
            }

            if (!allowedComponentTypes.contains(metadataComponentType)) {
                continue;
            }

            String fieldApiName = fieldApiNameByComponentId.get(refComponentId);
            String dedupeKey = categoryKey + ':' + metadataComponentType + ':' + metadataComponentName + ':' + fieldApiName;
            if (dedupeKeys.contains(dedupeKey)) {
                continue;
            }
            dedupeKeys.add(dedupeKey);

            results.add(new FieldUsageAnalyzerService.UsageResult(
                metadataComponentType,
                metadataComponentName,
                'Referenced via MetadataComponentDependency',
                fieldApiName
            ));
        }
        return results;
    }

    private List<FieldUsageAnalyzerService.UsageResult> findFlexiPageUsages(
        String objectApiName,
        List<String> fieldApiNames,
        Set<String> dedupeKeys
    ) {
        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        for (Map<String, Object> row : getFlexiPageRows()) {
            String flexiPageId = (String) row.get('Id');
            if (String.isBlank(flexiPageId)) {
                continue;
            }

            Map<String, Object> detailRow = getFlexiPageDetail(flexiPageId);
            if (detailRow == null) {
                continue;
            }
            String fullName = (String) detailRow.get('FullName');
            if (String.isBlank(fullName)) {
                continue;
            }
            Object metadata = detailRow.get('Metadata');
            if (!metadataMentionsObject(metadata, objectApiName)) {
                continue;
            }

            for (String fieldApiName : fieldApiNames) {
                if (String.isBlank(fieldApiName) || !metadataContainsFieldReference(metadata, objectApiName, fieldApiName)) {
                    continue;
                }
                String dedupeKey = categoryKey + ':FlexiPage:' + fullName + ':' + fieldApiName;
                if (dedupeKeys.contains(dedupeKey)) {
                    continue;
                }
                dedupeKeys.add(dedupeKey);
                results.add(new FieldUsageAnalyzerService.UsageResult(
                    'FlexiPage',
                    fullName,
                    'Referenced in FlexiPage metadata',
                    fieldApiName
                ));
            }
        }
        return results;
    }

    @TestVisible
    private static List<Map<String, Object>> getFlexiPageRows() {
        if (Test.isRunningTest() && testFlexiPageRows != null) {
            return testFlexiPageRows;
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Object rowObj : ToolingApiRestClient.query('SELECT Id FROM FlexiPage')) {
            rows.add((Map<String, Object>) rowObj);
        }
        return rows;
    }

    @TestVisible
    private static Map<String, Object> getFlexiPageDetail(String flexiPageId) {
        if (Test.isRunningTest() && testFlexiPageDetailsById != null) {
            return testFlexiPageDetailsById.get(flexiPageId);
        }
        List<Object> detailRows = ToolingApiRestClient.query(
            'SELECT Id, FullName, Metadata FROM FlexiPage WHERE Id = \'' +
            String.escapeSingleQuotes(flexiPageId) + '\''
        );
        return detailRows.isEmpty() ? null : (Map<String, Object>) detailRows[0];
    }

    @TestVisible
    private static String buildDependencyQuery(Set<String> fieldComponentIds) {
        List<String> quotedIds = new List<String>();
        for (String fieldComponentId : fieldComponentIds) {
            quotedIds.add('\'' + String.escapeSingleQuotes(fieldComponentId) + '\'');
        }

        String inClause = '(' + String.join(quotedIds, ',') + ')';
        return
            'SELECT MetadataComponentName, MetadataComponentType, RefMetadataComponentId, RefMetadataComponentType ' +
            'FROM MetadataComponentDependency ' +
            'WHERE RefMetadataComponentId IN ' + inClause;
    }

    @TestVisible
    private static Map<String, String> resolveFieldComponentIds(String objectApiName, List<String> fieldApiNames) {
        Map<String, String> fieldApiNameByComponentId = new Map<String, String>();
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return fieldApiNameByComponentId;
        }

        Set<String> requestedFields = new Set<String>(fieldApiNames);
        for (FieldDefinition fieldDef : [
            SELECT DurableId, QualifiedApiName
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :objectApiName
            AND QualifiedApiName IN :requestedFields
        ]) {
            String componentId = extractMetadataComponentId(fieldDef.DurableId);
            if (!String.isBlank(componentId)) {
                fieldApiNameByComponentId.put(componentId, fieldDef.QualifiedApiName);
            }
        }
        return fieldApiNameByComponentId;
    }

    @TestVisible
    private static String normalizeMetadataComponentId(String componentId) {
        if (String.isBlank(componentId)) {
            return componentId;
        }
        String trimmedId = componentId.trim();
        return trimmedId.length() == 18 ? trimmedId.substring(0, 15) : trimmedId;
    }

    @TestVisible
    private static String extractMetadataComponentId(String durableId) {
        if (String.isBlank(durableId)) {
            return null;
        }
        Integer separatorIndex = durableId.lastIndexOf('.');
        return separatorIndex >= 0 ? durableId.substring(separatorIndex + 1) : durableId;
    }

    @TestVisible
    private static Boolean textContainsFieldReference(String text, String objectApiName, String fieldApiName) {
        if (String.isBlank(text) || String.isBlank(objectApiName) || String.isBlank(fieldApiName)) {
            return false;
        }

        String lowerText = text.toLowerCase();
        String qualifiedField = objectApiName.toLowerCase() + '.' + fieldApiName.toLowerCase();
        return lowerText.contains('{!' + qualifiedField + '}') ||
            lowerText.contains(qualifiedField) ||
            lowerText.contains(fieldApiName.toLowerCase());
    }

    @TestVisible
    private static Boolean metadataContainsFieldReference(Object metadata, String objectApiName, String fieldApiName) {
        if (metadata == null || String.isBlank(fieldApiName)) {
            return false;
        }
        if (metadata instanceof Map<String, Object>) {
            for (Object childValue : ((Map<String, Object>) metadata).values()) {
                if (metadataContainsFieldReference(childValue, objectApiName, fieldApiName)) {
                    return true;
                }
            }
            return false;
        }
        if (metadata instanceof List<Object>) {
            for (Object childValue : (List<Object>) metadata) {
                if (metadataContainsFieldReference(childValue, objectApiName, fieldApiName)) {
                    return true;
                }
            }
            return false;
        }
        return textContainsFieldReference(String.valueOf(metadata), objectApiName, fieldApiName);
    }

    @TestVisible
    private static Boolean metadataMentionsObject(Object metadata, String objectApiName) {
        if (metadata == null || String.isBlank(objectApiName)) {
            return false;
        }
        if (metadata instanceof Map<String, Object>) {
            for (Object childValue : ((Map<String, Object>) metadata).values()) {
                if (metadataMentionsObject(childValue, objectApiName)) {
                    return true;
                }
            }
            return false;
        }
        if (metadata instanceof List<Object>) {
            for (Object childValue : (List<Object>) metadata) {
                if (metadataMentionsObject(childValue, objectApiName)) {
                    return true;
                }
            }
            return false;
        }

        return String.valueOf(metadata).toLowerCase().contains(objectApiName.toLowerCase());
    }
}

/**
 * WorkflowUsageProvider
 * ---------------------
 * Best-effort provider for legacy Workflow Rules / Field Updates.
 *
 * In this org, WorkflowRule metadata is queryable through Tooling SOAP, but
 * MetadataComponentDependency does not emit WorkflowRule rows for field
 * criteria or field update targets. We therefore read WorkflowRule metadata
 * directly and correlate any FieldUpdate actions back to WorkflowFieldUpdate
 * metadata.
 */
public with sharing class WorkflowUsageProvider implements IMetadataUsageProvider {

    public String getCategoryKey() {
        return 'WORKFLOW_PROCESS';
    }

    public List<FieldUsageAnalyzerService.UsageResult> findUsages(
        String objectApiName,
        List<String> fieldApiNames
    ) {
        List<FieldUsageAnalyzerService.UsageResult> results = new List<FieldUsageAnalyzerService.UsageResult>();
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return results;
        }

        Map<String, String> normalizedFields = normalizeFieldNames(fieldApiNames);
        Map<String, String> workflowFieldByActionName = loadWorkflowFieldTargets(normalizedFields.keySet());
        Set<String> dedupeKeys = new Set<String>();

        for (Map<String, Object> workflowRule : queryWorkflowRules(objectApiName)) {
            String workflowName = (String) workflowRule.get('FullName');
            Map<String, Object> metadata = asMap(workflowRule.get('Metadata'));
            if (String.isBlank(workflowName) || metadata == null) {
                continue;
            }

            addCriteriaMatches(results, dedupeKeys, workflowName, metadata.get('criteriaItems'), objectApiName, normalizedFields);
            addFieldUpdateMatches(results, dedupeKeys, workflowName, metadata, normalizedFields, workflowFieldByActionName);
        }

        return results;
    }

    @TestVisible
    private static List<Map<String, Object>> queryWorkflowRules(String objectApiName) {
        List<Map<String, Object>> rules = new List<Map<String, Object>>();
        String idSoql =
            'SELECT Id ' +
            'FROM WorkflowRule ' +
            'WHERE TableEnumOrId = \'' + String.escapeSingleQuotes(objectApiName) + '\'';

        for (Object rowObj : ToolingApiRestClient.query(idSoql)) {
            Map<String, Object> row = asMap(rowObj);
            String workflowRuleId = row == null ? null : (String) row.get('Id');
            if (String.isBlank(workflowRuleId)) {
                continue;
            }

            List<Object> detailRows = ToolingApiRestClient.query(
                'SELECT Id, FullName, TableEnumOrId, Metadata ' +
                'FROM WorkflowRule ' +
                'WHERE Id = \'' + String.escapeSingleQuotes(workflowRuleId) + '\''
            );
            if (!detailRows.isEmpty()) {
                rules.add(asMap(detailRows[0]));
            }
        }
        return rules;
    }

    @TestVisible
    private static Map<String, String> loadWorkflowFieldTargets(Set<String> normalizedFields) {
        Map<String, String> fieldByActionName = new Map<String, String>();
        for (Map<String, Object> workflowFieldUpdate : queryWorkflowFieldUpdates()) {
            String actionName = (String) workflowFieldUpdate.get('Name');
            Map<String, Object> metadata = asMap(workflowFieldUpdate.get('Metadata'));
            String fieldApiName = extractFieldApiName((String) metadata.get('field'));
            if (String.isBlank(actionName) || String.isBlank(fieldApiName)) {
                continue;
            }
            if (!normalizedFields.contains(fieldApiName.toLowerCase())) {
                continue;
            }
            fieldByActionName.put(normalizeActionName(actionName), fieldApiName);
            if (metadata != null && !String.isBlank((String) metadata.get('name'))) {
                fieldByActionName.put(normalizeActionName((String) metadata.get('name')), fieldApiName);
            }
        }
        return fieldByActionName;
    }

    @TestVisible
    private static List<Map<String, Object>> queryWorkflowFieldUpdates() {
        List<Map<String, Object>> fieldUpdates = new List<Map<String, Object>>();
        for (Object rowObj : ToolingApiRestClient.query('SELECT Id FROM WorkflowFieldUpdate')) {
            Map<String, Object> row = asMap(rowObj);
            String fieldUpdateId = row == null ? null : (String) row.get('Id');
            if (String.isBlank(fieldUpdateId)) {
                continue;
            }

            List<Object> detailRows = ToolingApiRestClient.query(
                'SELECT Id, Name, Metadata FROM WorkflowFieldUpdate ' +
                'WHERE Id = \'' + String.escapeSingleQuotes(fieldUpdateId) + '\''
            );
            if (!detailRows.isEmpty()) {
                fieldUpdates.add(asMap(detailRows[0]));
            }
        }
        return fieldUpdates;
    }

    private static void addCriteriaMatches(
        List<FieldUsageAnalyzerService.UsageResult> results,
        Set<String> dedupeKeys,
        String workflowName,
        Object criteriaItems,
        String objectApiName,
        Map<String, String> normalizedFields
    ) {
        for (Map<String, Object> criteriaItem : asMapList(criteriaItems)) {
            String fieldReference = (String) criteriaItem.get('field');
            String fieldApiName = extractFieldApiName(fieldReference);
            if (String.isBlank(fieldApiName) || !normalizedFields.containsKey(fieldApiName.toLowerCase())) {
                continue;
            }
            if (!isMatchingObjectReference(fieldReference, objectApiName)) {
                continue;
            }

            addUsageResult(
                results,
                dedupeKeys,
                'WorkflowRule',
                workflowName,
                'Referenced in workflow rule criteria',
                normalizedFields.get(fieldApiName.toLowerCase())
            );
        }
    }

    private static void addFieldUpdateMatches(
        List<FieldUsageAnalyzerService.UsageResult> results,
        Set<String> dedupeKeys,
        String workflowName,
        Map<String, Object> workflowMetadata,
        Map<String, String> normalizedFields,
        Map<String, String> workflowFieldByActionName
    ) {
        for (Map<String, Object> action : collectWorkflowActions(workflowMetadata)) {
            if ((String) action.get('type') != 'FieldUpdate') {
                continue;
            }

            String fieldApiName = workflowFieldByActionName.get(normalizeActionName((String) action.get('name')));
            if (String.isBlank(fieldApiName) || !normalizedFields.containsKey(fieldApiName.toLowerCase())) {
                continue;
            }

            addUsageResult(
                results,
                dedupeKeys,
                'WorkflowRule',
                workflowName,
                'Referenced via workflow field update action',
                normalizedFields.get(fieldApiName.toLowerCase())
            );
        }
    }

    @TestVisible
    private static List<Map<String, Object>> collectWorkflowActions(Map<String, Object> workflowMetadata) {
        List<Map<String, Object>> actions = new List<Map<String, Object>>();
        if (workflowMetadata == null) {
            return actions;
        }

        actions.addAll(asMapList(workflowMetadata.get('actions')));
        for (Map<String, Object> timeTrigger : asMapList(workflowMetadata.get('workflowTimeTriggers'))) {
            actions.addAll(asMapList(timeTrigger.get('actions')));
        }
        return actions;
    }

    @TestVisible
    private static String extractFieldApiName(String fieldReference) {
        if (String.isBlank(fieldReference)) {
            return null;
        }
        Integer separatorIndex = fieldReference.lastIndexOf('.');
        return separatorIndex >= 0 ? fieldReference.substring(separatorIndex + 1) : fieldReference;
    }

    @TestVisible
    private static Boolean isMatchingObjectReference(String fieldReference, String objectApiName) {
        if (String.isBlank(fieldReference) || String.isBlank(objectApiName)) {
            return false;
        }
        Integer separatorIndex = fieldReference.indexOf('.');
        if (separatorIndex < 0) {
            return true;
        }
        return fieldReference.substring(0, separatorIndex).toLowerCase() == objectApiName.toLowerCase();
    }

    private static void addUsageResult(
        List<FieldUsageAnalyzerService.UsageResult> results,
        Set<String> dedupeKeys,
        String componentType,
        String componentName,
        String context,
        String fieldApiName
    ) {
        String dedupeKey = componentType + ':' + componentName + ':' + fieldApiName + ':' + context;
        if (dedupeKeys.contains(dedupeKey)) {
            return;
        }
        dedupeKeys.add(dedupeKey);
        results.add(new FieldUsageAnalyzerService.UsageResult(componentType, componentName, context, fieldApiName));
    }

    @TestVisible
    private static String normalizeActionName(String actionName) {
        if (String.isBlank(actionName)) {
            return null;
        }

        String allowedChars = 'abcdefghijklmnopqrstuvwxyz0123456789';
        String normalized = '';
        for (Integer index = 0; index < actionName.length(); index++) {
            String character = actionName.substring(index, index + 1);
            if (allowedChars.contains(character.toLowerCase())) {
                normalized += character.toLowerCase();
            }
        }
        return normalized;
    }

    private static Map<String, String> normalizeFieldNames(List<String> fieldApiNames) {
        Map<String, String> normalizedFields = new Map<String, String>();
        if (fieldApiNames == null) {
            return normalizedFields;
        }

        for (String fieldApiName : fieldApiNames) {
            if (String.isBlank(fieldApiName)) {
                continue;
            }
            normalizedFields.put(fieldApiName.toLowerCase(), fieldApiName);
        }
        return normalizedFields;
    }

    @TestVisible
    private static Map<String, Object> asMap(Object value) {
        return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
    }

    @TestVisible
    private static List<Map<String, Object>> asMapList(Object value) {
        List<Map<String, Object>> maps = new List<Map<String, Object>>();
        if (value == null) {
            return maps;
        }
        if (value instanceof Map<String, Object>) {
            maps.add((Map<String, Object>) value);
            return maps;
        }
        if (value instanceof List<Object>) {
            for (Object item : (List<Object>) value) {
                if (item instanceof Map<String, Object>) {
                    maps.add((Map<String, Object>) item);
                }
            }
        }
        return maps;
    }
}

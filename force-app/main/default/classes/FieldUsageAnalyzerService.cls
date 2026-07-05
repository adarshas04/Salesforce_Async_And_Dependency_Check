public with sharing class FieldUsageAnalyzerService {

    public enum CategoryTier { DEFAULT_ON, OPTIONAL }

    public static List<CategoryDefinition> getCategoryDefinitions() {
        return new List<CategoryDefinition>{
            new CategoryDefinition('APEX', 'Apex Classes/Triggers', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('FLOW', 'Flows', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('VALIDATION_RULE', 'Validation Rules', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('CUSTOM_FIELD', 'Custom Fields (Formulas/Defaults)', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('LAYOUT', 'Page Layouts', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('FLEXIPAGE', 'Lightning Pages (FlexiPages)', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('EMAIL_TEMPLATE', 'Email Templates', CategoryTier.DEFAULT_ON),
            new CategoryDefinition('REPORT', 'Reports', CategoryTier.OPTIONAL),
            new CategoryDefinition('REPORT_TYPE', 'Report Types', CategoryTier.OPTIONAL),
            new CategoryDefinition('WORKFLOW_PROCESS', 'Workflow Rules / Process Builder', CategoryTier.OPTIONAL)
        };
    }

    public static AnalysisResponse analyze(String objectApiName,
                                            List<String> fieldApiNames,
                                            List<String> selectedCategories) {
        AnalysisResponse response = new AnalysisResponse();
        response.objectApiName = objectApiName;

        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        if (fieldApiNames == null || fieldApiNames.isEmpty()) {
            throw new AuraHandledException('At least one field must be selected.');
        }
        if (selectedCategories == null || selectedCategories.isEmpty()) {
            throw new AuraHandledException('At least one dependency category must be selected.');
        }

        List<String> canonicalFieldApiNames = canonicalizeFieldApiNames(objectApiName, fieldApiNames);
        response.fieldApiNames = canonicalFieldApiNames;

        Map<String, IMetadataUsageProvider> providersByCategory = getProviderRegistry();

        for (String category : selectedCategories) {
            IMetadataUsageProvider provider = providersByCategory.get(category);
            if (provider == null) {
                continue;
            }
            try {
                List<UsageResult> results = provider.findUsages(objectApiName, canonicalFieldApiNames);
                response.resultsByCategory.put(category, results);
            } catch (Exception ex) {
                // One bad provider should not blank the whole response.
                response.categoryErrors.put(category, ex.getMessage());
            }
        }
        return response;
    }

    @TestVisible
    private static List<String> canonicalizeFieldApiNames(String objectApiName, List<String> fieldApiNames) {
        List<String> canonicalFieldApiNames = new List<String>();
        if (String.isBlank(objectApiName) || fieldApiNames == null || fieldApiNames.isEmpty()) {
            return canonicalFieldApiNames;
        }
        Map<String, String> apiNameByLowercase = new Map<String, String>();
        for (FieldDefinition fieldDef : [
            SELECT QualifiedApiName
            FROM FieldDefinition
            WHERE EntityDefinition.QualifiedApiName = :objectApiName
        ]) {
            if (!String.isBlank(fieldDef.QualifiedApiName)) {
                apiNameByLowercase.put(fieldDef.QualifiedApiName.toLowerCase(), fieldDef.QualifiedApiName);
            }
        }

        Set<String> addedFieldApiNames = new Set<String>();
        for (String requestedFieldApiName : fieldApiNames) {
            if (String.isBlank(requestedFieldApiName)) {
                continue;
            }

            String canonicalFieldApiName = apiNameByLowercase.containsKey(requestedFieldApiName.toLowerCase())
                ? apiNameByLowercase.get(requestedFieldApiName.toLowerCase())
                : requestedFieldApiName;

            if (!addedFieldApiNames.contains(canonicalFieldApiName)) {
                addedFieldApiNames.add(canonicalFieldApiName);
                canonicalFieldApiNames.add(canonicalFieldApiName);
            }
        }
        return canonicalFieldApiNames;
    }

    private static Map<String, IMetadataUsageProvider> getProviderRegistry() {
        Map<String, IMetadataUsageProvider> registry = new Map<String, IMetadataUsageProvider>();
        for (String key : new List<String>{ 'APEX', 'FLOW', 'VALIDATION_RULE', 'CUSTOM_FIELD', 'LAYOUT', 'FLEXIPAGE', 'EMAIL_TEMPLATE' }) {
            registry.put(key, new ToolingDependencyUsageProvider(key));
        }
        registry.put('REPORT', new ReportUsageProvider('REPORT'));
        registry.put('REPORT_TYPE', new ReportUsageProvider('REPORT_TYPE'));
        registry.put('WORKFLOW_PROCESS', new WorkflowUsageProvider());
        return registry;
    }

    public class CategoryDefinition {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean defaultSelected;
        @AuraEnabled public String tier;

        public CategoryDefinition(String categoryKey, String label, CategoryTier tier) {
            this.categoryKey = categoryKey;
            this.label = label;
            this.tier = tier.name();
            this.defaultSelected = (tier == CategoryTier.DEFAULT_ON);
        }
    }

    public class UsageResult {
        @AuraEnabled public String componentType;
        @AuraEnabled public String componentName;
        @AuraEnabled public String context;
        @AuraEnabled public String fieldApiName;

        public UsageResult(String componentType, String componentName, String context, String fieldApiName) {
            this.componentType = componentType;
            this.componentName = componentName;
            this.context = context;
            this.fieldApiName = fieldApiName;
        }
    }

    public class AnalysisResponse {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public List<String> fieldApiNames;
        @AuraEnabled public Map<String, List<UsageResult>> resultsByCategory = new Map<String, List<UsageResult>>();
        @AuraEnabled public Map<String, String> categoryErrors = new Map<String, String>();
    }

    public class ProviderExecutionException extends Exception {}
}
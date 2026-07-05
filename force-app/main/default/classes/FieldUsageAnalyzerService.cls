/**
 * FieldUsageAnalyzerService
 * ---------------------------
 * Orchestrates "Where Is This Used?" analysis for one or more fields on a
 * selected object, replicating Salesforce's native dependency UI using the
 * Tooling API's MetadataComponentDependency object plus targeted lookups
 * only when a category doesn't surface cleanly through that object
 * (for example Reports / Report Types, or metadata fallbacks for layout/page
 * definitions in orgs where dependency rows are incomplete).
 *
 * UX/performance design:
 * ------------------------
 * Not all dependency categories cost the same to compute:
 *   - Apex, Flow, Validation Rules, Custom Field formulas/defaults, Layouts,
 *     FlexiPages, and Email Templates first attempt to resolve via a
 *     Tooling API query against
 *     MetadataComponentDependency - fast, so these are DEFAULT (pre-checked
 *     in the LWC and always included unless explicitly deselected).
 *   - Reports / Report Types require either walking ReportType columns via
 *     Tooling API or reading Report metadata - more expensive, and lower
 *     signal for most "safe to change this field?" questions. OPTIONAL.
 *   - Workflow Rules / Process Builder are legacy, but some orgs still
 *     need them reviewed. Workflow Rules often don't emit reliable
 *     MetadataComponentDependency rows, so this category uses a direct
 *     metadata read fallback and stays OPTIONAL.
 *
 * This registry-driven design means the LWC can render checkboxes purely
 * from getCategoryDefinitions() without hardcoding category lists on the
 * client, and new categories can be added by registering a new
 * IMetadataUsageProvider + one CategoryDefinition entry.
 */
public with sharing class FieldUsageAnalyzerService {

    public enum CategoryTier { DEFAULT_ON, OPTIONAL }

    /**
     * Returns the full set of dependency categories the LWC can render as
     * checkboxes, each flagged with whether it should be pre-selected.
     * Called once when the LWC loads (via ObjectMetadataController or
     * directly), so the UX stays flexible if categories are added/removed
     * server-side without a client deploy.
     */
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

    /**
     * Main analysis entry point invoked by the LWC's "Analyze Field Usage"
     * button. Only runs providers for the categories the user selected
     * (defaults pre-checked client-side, optional ones opt-in).
     */
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
                continue; // unknown category key - skip silently, don't fail whole analysis
            }
            try {
                List<UsageResult> results = provider.findUsages(objectApiName, canonicalFieldApiNames);
                response.resultsByCategory.put(category, results);
            } catch (Exception ex) {
                // Isolate failures per-category so one bad provider (e.g. a
                // Tooling API callout timing out) doesn't block the other
                // categories from returning results.
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

    // ---- Wrapper / DTO classes ----

    public class CategoryDefinition {
        @AuraEnabled public String categoryKey;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean defaultSelected;
        @AuraEnabled public String tier; // string form of CategoryTier for LWC consumption

        public CategoryDefinition(String categoryKey, String label, CategoryTier tier) {
            this.categoryKey = categoryKey;
            this.label = label;
            this.tier = tier.name();
            this.defaultSelected = (tier == CategoryTier.DEFAULT_ON);
        }
    }

    public class UsageResult {
        @AuraEnabled public String componentType;  // e.g. 'ApexClass', 'Flow', 'FlexiPage'
        @AuraEnabled public String componentName;
        @AuraEnabled public String context;         // e.g. line/section detail if available
        @AuraEnabled public String fieldApiName;     // which selected field this usage relates to

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

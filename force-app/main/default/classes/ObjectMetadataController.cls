public with sharing class ObjectMetadataController {

    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllObjects() {
        List<ObjectOption> options = new List<ObjectOption>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        for (String apiName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describe = globalDescribe.get(apiName).getDescribe();

            if (!describe.isQueryable() || !describe.isAccessible()) {
                continue;
            }
            if (apiName.endsWith('__History') || apiName.endsWith('__Share') ||
                apiName.endsWith('__Feed') || apiName.endsWith('__ChangeEvent')) {
                continue;
            }

            options.add(new ObjectOption(apiName, describe.getLabel()));
        }

        options.sort();
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldUsageAnalyzerService.CategoryDefinition> getCategoryDefinitions() {
        return FieldUsageAnalyzerService.getCategoryDefinitions();
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldOption> getFieldsForObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            return new List<FieldOption>();
        }

        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            throw new AuraHandledException('Unknown object: ' + objectApiName);
        }

        Schema.DescribeSObjectResult objectDescribe = objectType.getDescribe();
        if (!objectDescribe.isAccessible()) {
            throw new AuraHandledException('Object is not accessible: ' + objectApiName);
        }

        Map<String, Schema.SObjectField> fieldsByApiName = objectDescribe.fields.getMap();
        for (String fieldApiName : fieldsByApiName.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldsByApiName.get(fieldApiName).getDescribe();
            if (!fieldDescribe.isAccessible()) {
                continue;
            }
            String canonicalApiName = canonicalApiNameByLowercase.containsKey(fieldApiName.toLowerCase())
                ? canonicalApiNameByLowercase.get(fieldApiName.toLowerCase())
                : fieldApiName;
            options.add(new FieldOption(canonicalApiName, fieldDescribe.getLabel()));
        }

        options.sort();
        return options;
    }

    @AuraEnabled
    public static FieldUsageAnalyzerService.AnalysisResponse analyzeFieldUsage(
        String objectApiName,
        List<String> fieldApiNames,
        List<String> selectedCategories
    ) {
        try {
            return FieldUsageAnalyzerService.analyze(objectApiName, fieldApiNames, selectedCategories);
        } catch (Exception ex) {
            throw new AuraHandledException('Field usage analysis failed: ' + ex.getMessage());
        }
    }

    public class ObjectOption implements Comparable {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;

        public ObjectOption(String apiName, String label) {
            this.apiName = apiName;
            this.label = label;
        }

        public Integer compareTo(Object other) {
            ObjectOption o = (ObjectOption) other;
            return this.label.compareTo(o.label);
        }
    }

    public class FieldOption implements Comparable {
        @AuraEnabled public String apiName;
        @AuraEnabled public String label;

        public FieldOption(String apiName, String label) {
            this.apiName = apiName;
            this.label = label;
        }

        public Integer compareTo(Object other) {
            FieldOption o = (FieldOption) other;
            return this.label.compareTo(o.label);
        }
    }
}

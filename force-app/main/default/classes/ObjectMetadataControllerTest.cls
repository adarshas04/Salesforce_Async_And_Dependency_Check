@isTest
private class ObjectMetadataControllerTest {

    @isTest
    static void testGetAllObjects_returnsSortedAccessibleObjects() {
        Test.startTest();
        List<ObjectMetadataController.ObjectOption> options = ObjectMetadataController.getAllObjects();
        Test.stopTest();

        System.assert(!options.isEmpty(), 'Expected at least one queryable object to be returned.');

        Boolean foundAccount = false;
        for (ObjectMetadataController.ObjectOption o : options) {
            if (o.apiName == 'Account') {
                foundAccount = true;
            }
            // Spot-check noisy suffixes are filtered out.
            System.assert(!o.apiName.endsWith('__History'), 'History objects should be filtered out.');
            System.assert(!o.apiName.endsWith('__Share'), 'Share objects should be filtered out.');
        }
        System.assertEquals(true, foundAccount, 'Standard Account object should be present in results.');
    }

    @isTest
    static void testGetCategoryDefinitions_defaultsFlaggedCorrectly() {
        Test.startTest();
        List<FieldUsageAnalyzerService.CategoryDefinition> defs = ObjectMetadataController.getCategoryDefinitions();
        Test.stopTest();

        Map<String, FieldUsageAnalyzerService.CategoryDefinition> byKey =
            new Map<String, FieldUsageAnalyzerService.CategoryDefinition>();
        for (FieldUsageAnalyzerService.CategoryDefinition d : defs) {
            byKey.put(d.categoryKey, d);
        }

        System.assertEquals(true, byKey.get('APEX').defaultSelected, 'Apex should be a default-on category.');
        System.assertEquals(true, byKey.get('FLOW').defaultSelected, 'Flow should be a default-on category.');
        System.assertEquals(true, byKey.get('CUSTOM_FIELD').defaultSelected, 'Custom field dependencies should be default-on.');
        System.assertEquals(true, byKey.get('FLEXIPAGE').defaultSelected, 'FlexiPage should be a default-on category.');
        System.assertEquals(false, byKey.get('REPORT').defaultSelected, 'Report should remain optional.');
        System.assertEquals(false, byKey.get('WORKFLOW_PROCESS').defaultSelected, 'Workflow should be optional (not default).');
        System.assertEquals('OPTIONAL', byKey.get('WORKFLOW_PROCESS').tier, 'Workflow should be optional.');
    }

    @isTest
    static void testGetFieldsForObject_returnsAccessibleFields() {
        Test.startTest();
        List<ObjectMetadataController.FieldOption> fields =
            ObjectMetadataController.getFieldsForObject('Account');
        Test.stopTest();

        System.assert(!fields.isEmpty(), 'Expected Account fields to be returned.');

        Boolean foundName = false;
        for (ObjectMetadataController.FieldOption fieldOption : fields) {
            if (fieldOption.apiName == 'Name') {
                foundName = true;
                break;
            }
        }
        System.assertEquals(true, foundName, 'Standard Name field should be present.');
    }

    @isTest
    static void testGetFieldsForObject_includesPriorityField() {
        Test.startTest();
        List<ObjectMetadataController.FieldOption> fields =
            ObjectMetadataController.getFieldsForObject('Account');
        Test.stopTest();

        Boolean foundPriority = false;
        for (ObjectMetadataController.FieldOption fieldOption : fields) {
            if (fieldOption.apiName != null && fieldOption.apiName.toLowerCase() == 'priority__c') {
                foundPriority = true;
                break;
            }
        }

        System.assertEquals(true, foundPriority, 'Priority field should be available in the field picker.');
    }

    @isTest
    static void testGetFieldsForObject_rejectsUnknownObject() {
        Boolean threw = false;

        try {
            ObjectMetadataController.getFieldsForObject('Definitely_Not_A_Real_Object__c');
        } catch (AuraHandledException ex) {
            threw = true;
        }

        System.assertEquals(true, threw, 'Unknown objects should be rejected.');
    }

    @isTest
    static void testAnalyzeFieldUsage_delegatesToService() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = ObjectMetadataController.analyzeFieldUsage(
            'Account',
            new List<String>{ 'Score__c' },
            new List<String>{ 'FLOW' }
        );
        Test.stopTest();

        System.assertEquals('Account', response.objectApiName);
        System.assert(response.resultsByCategory.containsKey('FLOW'));
        System.assert(response.resultsByCategory.get('FLOW').size() > 0);
    }

    @isTest
    static void testAnalyzeFieldUsage_acceptsLowercaseFieldApiNameFromClient() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = ObjectMetadataController.analyzeFieldUsage(
            'Account',
            new List<String>{ 'score__c' },
            new List<String>{ 'FLOW' }
        );
        Test.stopTest();

        System.assertEquals('Score__c', response.fieldApiNames[0]);
        System.assertEquals(1, response.resultsByCategory.get('FLOW').size());
    }
}
@isTest
private class ToolingDependencyUsageProviderTest {

    @isTest
    static void testFindUsages_success() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('FLOW').findUsages('Account', new List<String>{ 'Score__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Flow', results[0].componentType);
        System.assertEquals('Account_After_Update', results[0].componentName);
    }

    @isTest
    static void testFindUsages_apexUsesDependencyQueryWhenAvailable() {
        Test.setMock(
            HttpCalloutMock.class,
            new DependencyByFieldIdMock('Account', 'Priority__c', 'ApexClass', 'AccountScoringService')
        );

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('APEX').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('ApexClass', results[0].componentType);
        System.assertEquals('AccountScoringService', results[0].componentName);
        System.assertEquals('Referenced via MetadataComponentDependency', results[0].context);
    }

    @isTest
    static void testFindUsages_customFieldDependencyIncluded() {
        Test.setMock(
            HttpCalloutMock.class,
            new DependencyByFieldIdMock('Account', 'Priority__c', 'CustomField', 'Priority_Score')
        );

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('CUSTOM_FIELD').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('CustomField', results[0].componentType);
        System.assertEquals('Priority_Score', results[0].componentName);
    }

    @isTest
    static void testFindUsages_normalizes18CharacterFieldIds() {
        Test.setMock(
            HttpCalloutMock.class,
            new DependencyByFieldIdMock('Account', 'Priority__c', 'Flow', 'Account_Priority_Flow', true)
        );

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('FLOW').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Account_Priority_Flow', results[0].componentName);
    }

    @isTest
    static void testFindUsages_handlesPaginatedToolingResponses() {
        Test.setMock(HttpCalloutMock.class, new PaginatedDependencyMock());

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('FLOW').findUsages('Account', new List<String>{ 'Score__c' });
        Test.stopTest();

        System.assertEquals(2, results.size());
        Set<String> componentNames = new Set<String>();
        for (FieldUsageAnalyzerService.UsageResult result : results) {
            componentNames.add(result.componentName);
        }
        System.assert(componentNames.contains('Account_After_Update'));
        System.assert(componentNames.contains('Account_Before_Save'));
    }

    @isTest
    static void testFindUsages_calloutFailureSurfacesCategoryError() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.FailureMock());

        Boolean threw = false;
        try {
            Test.startTest();
            new ToolingDependencyUsageProvider('FLOW').findUsages('Account', new List<String>{ 'Score__c' });
            Test.stopTest();
        } catch (Exception ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Dependency lookup failed.'));
        }

        System.assertEquals(true, threw);
    }

    @isTest
    static void testHelperMethods_coverNormalizationBranches() {
        System.assert(
            ToolingDependencyUsageProvider.buildDependencyQuery(new Set<String>{ '00NgK0000001234' }).contains('RefMetadataComponentId IN')
        );
        System.assertEquals(0, ToolingDependencyUsageProvider.resolveFieldComponentIds(null, new List<String>{ 'Priority__c' }).size());
        System.assertEquals('00NABC123456789', ToolingDependencyUsageProvider.normalizeMetadataComponentId('00NABC123456789XYZ'));
        System.assertEquals(null, ToolingDependencyUsageProvider.extractMetadataComponentId(null));
        System.assertEquals('MyField__c', ToolingDependencyUsageProvider.extractMetadataComponentId('Account.MyField__c'));
        System.assertEquals(true, ToolingDependencyUsageProvider.textContainsFieldReference('{!Account.Priority__c}', 'Account', 'Priority__c'));
        System.assertEquals(false, ToolingDependencyUsageProvider.textContainsFieldReference('{!Contact.Email}', 'Account', 'Priority__c'));
    }

    @isTest
    static void testMetadataFallbackHelpers_scanNestedMetadata() {
        Map<String, Object> metadata = new Map<String, Object>{
            'entity' => 'Account',
            'regions' => new List<Object>{
                new Map<String, Object>{
                    'items' => new List<Object>{
                        new Map<String, Object>{ 'field' => 'Priority__c' }
                    }
                }
            }
        };

        System.assertEquals(true, ToolingDependencyUsageProvider.metadataMentionsObject(metadata, 'Account'));
        System.assertEquals(true, ToolingDependencyUsageProvider.metadataContainsFieldReference(metadata, 'Account', 'Priority__c'));
        System.assertEquals(false, ToolingDependencyUsageProvider.metadataContainsFieldReference(metadata, 'Account', 'Score__c'));
    }

    @isTest
    static void testFindUsages_flexiPageFallback() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.EmptyResultMock());
        ToolingDependencyUsageProvider.testFlexiPageRows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'Id' => '0M0xx0000000001AAA' }
        };
        ToolingDependencyUsageProvider.testFlexiPageDetailsById = new Map<String, Map<String, Object>>{
            '0M0xx0000000001AAA' => new Map<String, Object>{
                'Id' => '0M0xx0000000001AAA',
                'FullName' => 'Account_Record_Page',
                'Metadata' => new Map<String, Object>{
                    'sobjectType' => 'Account',
                    'flexiPageRegions' => new List<Object>{
                        new Map<String, Object>{
                            'itemInstances' => new List<Object>{
                                new Map<String, Object>{
                                    'fieldInstance' => new Map<String, Object>{ 'fieldItem' => 'Priority__c' }
                                }
                            }
                        }
                    }
                }
            }
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ToolingDependencyUsageProvider('FLEXIPAGE').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('FlexiPage', results[0].componentType);
        System.assertEquals('Account_Record_Page', results[0].componentName);
        ToolingDependencyUsageProvider.testFlexiPageRows = null;
        ToolingDependencyUsageProvider.testFlexiPageDetailsById = null;
    }

    @isTest
    static void testFindUsages_unknownCategoryAndMissingFieldsReturnEmpty() {
        System.assertEquals(
            0,
            new ToolingDependencyUsageProvider('UNKNOWN').findUsages('Account', new List<String>{ 'Priority__c' }).size()
        );
        System.assertEquals(
            0,
            new ToolingDependencyUsageProvider().findUsages('Account', new List<String>()).size()
        );
    }

    @isTest
    static void testGetCategoryKey() {
        System.assertEquals('APEX', new ToolingDependencyUsageProvider().getCategoryKey());
    }

    private class DependencyByFieldIdMock implements HttpCalloutMock {
        private final String objectApiName;
        private final String fieldApiName;
        private final String componentType;
        private final String componentName;
        private final Boolean use18CharId;

        private DependencyByFieldIdMock(String objectApiName, String fieldApiName, String componentType, String componentName) {
            this(objectApiName, fieldApiName, componentType, componentName, false);
        }

        private DependencyByFieldIdMock(
            String objectApiName,
            String fieldApiName,
            String componentType,
            String componentName,
            Boolean use18CharId
        ) {
            this.objectApiName = objectApiName;
            this.fieldApiName = fieldApiName;
            this.componentType = componentType;
            this.componentName = componentName;
            this.use18CharId = use18CharId;
        }

        public HTTPResponse respond(HTTPRequest req) {
            String fieldComponentId = ToolingApiMocks.findFieldComponentId(objectApiName, fieldApiName);
            if (use18CharId == true) {
                fieldComponentId += 'UAL';
            }

            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                new Map<String, Object>{
                    'MetadataComponentType' => componentType,
                    'MetadataComponentName' => componentName,
                    'RefMetadataComponentId' => fieldComponentId,
                    'RefMetadataComponentType' => 'CustomField'
                }
            }));
            return res;
        }
    }

    private class PaginatedDependencyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/tooling/query/')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                    new Map<String, Object>{
                        'MetadataComponentType' => 'Flow',
                        'MetadataComponentName' => 'Account_Before_Save',
                        'RefMetadataComponentId' => ToolingApiMocks.findFieldComponentId('Account', 'Score__c'),
                        'RefMetadataComponentType' => 'CustomField'
                    }
                }));
                return res;
            }

            res.setBody(ToolingApiMocks.buildRestQueryResponse(
                new List<Object>{
                    new Map<String, Object>{
                        'MetadataComponentType' => 'Flow',
                        'MetadataComponentName' => 'Account_After_Update',
                        'RefMetadataComponentId' => ToolingApiMocks.findFieldComponentId('Account', 'Score__c'),
                        'RefMetadataComponentType' => 'CustomField'
                    }
                },
                false,
                '/services/data/v60.0/tooling/query/01gxx0000000001AAA-2000'
            ));
            return res;
        }
    }
}

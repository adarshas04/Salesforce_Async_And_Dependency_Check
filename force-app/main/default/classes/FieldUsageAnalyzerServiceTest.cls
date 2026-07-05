@isTest
private class FieldUsageAnalyzerServiceTest {

    @isTest
    static void testAnalyze_defaultCategoryReturnsResults() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = FieldUsageAnalyzerService.analyze(
            'Account',
            new List<String>{ 'Score__c' },
            new List<String>{ 'APEX', 'FLOW', 'CUSTOM_FIELD' }
        );
        Test.stopTest();

        System.assert(response.resultsByCategory.containsKey('APEX'));
        System.assert(response.resultsByCategory.containsKey('FLOW'));
        System.assert(response.resultsByCategory.containsKey('CUSTOM_FIELD'));
        System.assertEquals(0, response.categoryErrors.size(), 'No callout failures expected in this scenario.');
    }

    @isTest
    static void testAnalyze_emptyResultsHandledGracefully() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.EmptyResultMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = FieldUsageAnalyzerService.analyze(
            'Account',
            new List<String>{ 'Score__c' },
            new List<String>{ 'FLOW' }
        );
        Test.stopTest();

        System.assertEquals(0, response.resultsByCategory.get('FLOW').size());
    }

    @isTest
    static void testAnalyze_unknownCategoryIsSkipped() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = FieldUsageAnalyzerService.analyze(
            'Account',
            new List<String>{ 'Score__c' },
            new List<String>{ 'NOT_A_REAL_CATEGORY' }
        );
        Test.stopTest();

        System.assertEquals(0, response.resultsByCategory.size(), 'Unknown category keys should be skipped, not error.');
        System.assertEquals(0, response.categoryErrors.size());
    }

    @isTest
    static void testAnalyze_canonicalizesLowercaseFieldApiNames() {
        Test.setMock(HttpCalloutMock.class, new ToolingApiMocks.DependencySuccessMock());

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = FieldUsageAnalyzerService.analyze(
            'Account',
            new List<String>{ 'score__c' },
            new List<String>{ 'FLOW' }
        );
        Test.stopTest();

        System.assertEquals('Score__c', response.fieldApiNames[0], 'Field names should be normalized to the describe-canonical API name.');
        System.assertEquals(1, response.resultsByCategory.get('FLOW').size(), 'Lowercase field selections should still produce dependency matches.');
    }

    @isTest
    static void testAnalyze_reportCategoryMatchesFieldReference() {
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Account Priority Report',
                '{"reportMetadata":{"name":"Account Priority Report"},"reportType":{"label":"Accounts and Scores"},"detailColumns":["ACCOUNT.SCORE__C"],"scope":"Account"}'
            )
        };

        Test.startTest();
        FieldUsageAnalyzerService.AnalysisResponse response = FieldUsageAnalyzerService.analyze(
            'Account',
            new List<String>{ 'Score__c' },
            new List<String>{ 'REPORT' }
        );
        Test.stopTest();

        System.assert(response.resultsByCategory.containsKey('REPORT'));
        System.assertEquals(1, response.resultsByCategory.get('REPORT').size());
        ReportUsageProvider.testReportDescriptors = null;
    }

    @isTest
    static void testGetCategoryDefinitions_containsAllExpectedTiers() {
        Test.startTest();
        List<FieldUsageAnalyzerService.CategoryDefinition> defs = FieldUsageAnalyzerService.getCategoryDefinitions();
        Test.stopTest();

        Set<String> tiersSeen = new Set<String>();
        Set<String> keysSeen = new Set<String>();
        for (FieldUsageAnalyzerService.CategoryDefinition d : defs) {
            tiersSeen.add(d.tier);
            keysSeen.add(d.categoryKey);
        }
        System.assert(tiersSeen.contains('DEFAULT_ON'));
        System.assert(tiersSeen.contains('OPTIONAL'));
        System.assert(keysSeen.contains('CUSTOM_FIELD'));
    }

    @isTest
    static void testCanonicalizeFieldApiNames_preservesOrderAndDedupes() {
        Test.startTest();
        List<String> canonical = FieldUsageAnalyzerService.canonicalizeFieldApiNames(
            'Account',
            new List<String>{ 'score__c', 'SCORE__C', 'name' }
        );
        Test.stopTest();

        System.assertEquals(
            new List<String>{ 'Score__c', 'Name' },
            canonical
        );
    }
}

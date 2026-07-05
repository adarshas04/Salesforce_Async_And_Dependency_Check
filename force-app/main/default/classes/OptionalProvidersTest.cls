@isTest
private class OptionalProvidersTest {

    @isTest
    static void testReportUsageProvider_matchFound() {
        ReportUsageProvider.testReportTypeRecords = new List<ReportTypeMetadataClient.ReportTypeRecord>{
            buildReportTypeRecord('Account_Custom', 'Account Custom', 'Account', new List<ReportTypeMetadataClient.ColumnReference>{
                new ReportTypeMetadataClient.ColumnReference('Account', 'Priority__c')
            })
        };

        Test.startTest();
        ReportUsageProvider provider = new ReportUsageProvider('REPORT_TYPE');
        List<FieldUsageAnalyzerService.UsageResult> results =
            provider.findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('ReportType', results[0].componentType);
        System.assertEquals('Account Custom', results[0].componentName);
        ReportUsageProvider.testReportDescriptors = null;
        ReportUsageProvider.testReportTypeRecords = null;
    }

    @isTest
    static void testReportUsageProvider_reportMatchFound() {
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Account Priority Report',
                '{"reportMetadata":{"name":"Account Priority Report"},"detailColumns":["ACCOUNT.SCORE__C"],"scope":"Account"}'
            )
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ReportUsageProvider('REPORT').findUsages('Account', new List<String>{ 'Score__c' });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals('Report', results[0].componentType);
        ReportUsageProvider.testReportDescriptors = null;
    }

    @isTest
    static void testReportUsageProvider_reportTypeFailureDoesNotInferFromReports() {
        ReportUsageProvider.testReportTypeFailureMessage = 'INVALID_SESSION_ID: This session is not valid for use with the API';
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Account Priority Report',
                '{"reportMetadata":{"name":"Account Priority Report"},"reportType":{"label":"Account Custom"},"detailColumns":["ACCOUNT.PRIORITY__C"],"scope":"Account"}'
            )
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ReportUsageProvider('REPORT_TYPE').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(0, results.size());
        ReportUsageProvider.testReportDescriptors = null;
        ReportUsageProvider.testReportTypeFailureMessage = null;
    }

    @isTest
    static void testReportUsageProvider_noMatchReturnsEmpty() {
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Unrelated Opportunity Report',
                '{"reportMetadata":{"name":"Unrelated Opportunity Report"},"detailColumns":["OPPORTUNITY.AMOUNT"],"scope":"Opportunity"}'
            )
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ReportUsageProvider('REPORT').findUsages('Account', new List<String>{ 'Score__c' });
        Test.stopTest();

        System.assertEquals(0, results.size());
        ReportUsageProvider.testReportDescriptors = null;
        ReportUsageProvider.testReportTypeRecords = null;
    }

    @isTest
    static void testReportUsageProvider_ignoresDifferentObjectFieldReference() {
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Log Entry Priority Report',
                '{"reportMetadata":{"name":"Log Entry Priority Report"},"detailColumns":["LOG__C.PRIORITY__C"],"scope":"Account"}'
            )
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ReportUsageProvider('REPORT').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(0, results.size());
        ReportUsageProvider.testReportDescriptors = null;
    }

    @isTest
    static void testReportUsageProvider_reportTypeFailureStillReturnsEmpty() {
        ReportUsageProvider.testReportTypeFailureMessage = 'INVALID_SESSION_ID: This session is not valid for use with the API';
        ReportUsageProvider.testReportDescriptors = new List<ReportUsageProvider.ReportDescriptor>{
            new ReportUsageProvider.ReportDescriptor(
                'Log Entry Priority Report',
                '{"reportMetadata":{"name":"Log Entry Priority Report"},"reportType":{"label":"Log Entries"},"detailColumns":["LOG__C.PRIORITY__C"],"scope":"Account"}'
            )
        };

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new ReportUsageProvider('REPORT_TYPE').findUsages('Account', new List<String>{ 'Priority__c' });
        Test.stopTest();

        System.assertEquals(0, results.size());
        ReportUsageProvider.testReportDescriptors = null;
        ReportUsageProvider.testReportTypeFailureMessage = null;
    }

    @isTest
    static void testContainsQualifiedFieldReference_matchesOnlySameObject() {
        System.assertEquals(
            true,
            ReportUsageProvider.containsQualifiedFieldReference(
                '{"detailColumns":["ACCOUNT.PRIORITY__C"]}',
                'Account',
                'Priority__c'
            )
        );
        System.assertEquals(
            false,
            ReportUsageProvider.containsQualifiedFieldReference(
                '{"detailColumns":["LOG__C.PRIORITY__C"],"scope":"Account"}',
                'Account',
                'Priority__c'
            )
        );
    }

    @isTest
    static void testReportUsageProvider_recoversOnlyForSessionFailures() {
        System.assertEquals(
            true,
            ReportUsageProvider.isRecoverableReportTypeMetadataFailure(
                new FieldUsageAnalyzerService.ProviderExecutionException('INVALID_SESSION_ID: This session is not valid for use with the API')
            )
        );
        System.assertEquals(
            false,
            ReportUsageProvider.isRecoverableReportTypeMetadataFailure(
                new FieldUsageAnalyzerService.ProviderExecutionException('Metadata API call failed [500]: unexpected fault')
            )
        );
    }

    @isTest
    static void testReportUsageProvider_categoryKey() {
        System.assertEquals('REPORT', new ReportUsageProvider().getCategoryKey());
        System.assertEquals('REPORT_TYPE', new ReportUsageProvider('REPORT_TYPE').getCategoryKey());
    }

    private static ReportTypeMetadataClient.ReportTypeRecord buildReportTypeRecord(
        String fullName,
        String label,
        String baseObject,
        List<ReportTypeMetadataClient.ColumnReference> columns
    ) {
        ReportTypeMetadataClient.ReportTypeRecord record = new ReportTypeMetadataClient.ReportTypeRecord();
        record.fullName = fullName;
        record.label = label;
        record.baseObject = baseObject;
        record.columnReferences.addAll(columns);
        return record;
    }

    @isTest
    static void testWorkflowUsageProvider_matchesCriteriaAndFieldUpdate() {
        Test.setMock(HttpCalloutMock.class, new WorkflowMetadataMock());

        Test.startTest();
        List<FieldUsageAnalyzerService.UsageResult> results =
            new WorkflowUsageProvider().findUsages('Account', new List<String>{ 'Priority__c', 'Score__c' });
        Test.stopTest();

        System.assertEquals(2, results.size());
        Map<String, FieldUsageAnalyzerService.UsageResult> byField = new Map<String, FieldUsageAnalyzerService.UsageResult>();
        for (FieldUsageAnalyzerService.UsageResult result : results) {
            byField.put(result.fieldApiName, result);
            System.assertEquals('WorkflowRule', result.componentType);
            System.assertEquals('Account.Test', result.componentName);
        }
        System.assertEquals('Referenced in workflow rule criteria', byField.get('Priority__c').context);
        System.assertEquals('Referenced via workflow field update action', byField.get('Score__c').context);
    }

    @isTest
    static void testWorkflowUsageProvider_categoryKey() {
        System.assertEquals('WORKFLOW_PROCESS', new WorkflowUsageProvider().getCategoryKey());
    }

    @isTest
    static void testWorkflowUsageProvider_helpers() {
        System.assertEquals('Priority__c', WorkflowUsageProvider.extractFieldApiName('Account.Priority__c'));
        System.assertEquals(true, WorkflowUsageProvider.isMatchingObjectReference('Account.Priority__c', 'Account'));
        System.assertEquals(false, WorkflowUsageProvider.isMatchingObjectReference('Log__c.Priority__c', 'Account'));
        System.assertEquals('updatescore', WorkflowUsageProvider.normalizeActionName('Update Score'));
        System.assertEquals('updatescore', WorkflowUsageProvider.normalizeActionName('Update_Score'));

        List<Map<String, Object>> actions = WorkflowUsageProvider.collectWorkflowActions(new Map<String, Object>{
            'actions' => new Map<String, Object>{ 'type' => 'FieldUpdate', 'name' => 'Immediate' },
            'workflowTimeTriggers' => new List<Object>{
                new Map<String, Object>{
                    'actions' => new List<Object>{
                        new Map<String, Object>{ 'type' => 'FieldUpdate', 'name' => 'Scheduled' }
                    }
                }
            }
        });
        System.assertEquals(2, actions.size());
    }

    private class WorkflowMetadataMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            String endpoint = req.getEndpoint();

            if (endpoint != null && endpoint.contains('SELECT+Id+FROM+WorkflowRule')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                    new Map<String, Object>{ 'Id' => '01QgK000002tXDVUA2' }
                }));
                return res;
            }

            if (endpoint != null && endpoint.contains('FROM+WorkflowRule')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                    new Map<String, Object>{
                        'Id' => '01QgK000002tXDVUA2',
                        'FullName' => 'Account.Test',
                        'TableEnumOrId' => 'Account',
                        'Metadata' => new Map<String, Object>{
                            'criteriaItems' => new Map<String, Object>{
                                'field' => 'Account.Priority__c',
                                'operation' => 'equals',
                                'value' => 'High Priority'
                            },
                            'actions' => new Map<String, Object>{
                                'type' => 'FieldUpdate',
                                'name' => 'Update_Score'
                            }
                        }
                    }
                }));
                return res;
            }

            if (endpoint != null && endpoint.contains('SELECT+Id+FROM+WorkflowFieldUpdate')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                    new Map<String, Object>{ 'Id' => '04XgK0000000001AAA' }
                }));
                return res;
            }

            if (endpoint != null && endpoint.contains('FROM+WorkflowFieldUpdate')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>{
                    new Map<String, Object>{
                        'Id' => '04XgK0000000001AAA',
                        'Name' => 'Update_Score',
                        'Metadata' => new Map<String, Object>{
                            'field' => 'Account.Score__c'
                        }
                    }
                }));
                return res;
            }

            res.setBody(ToolingApiMocks.buildRestQueryResponse(new List<Object>()));
            return res;
        }
    }
}

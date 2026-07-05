@isTest
private class ToolingApiRestClientTest {

    @isTest
    static void testQuery_handlesPagination() {
        Test.setMock(HttpCalloutMock.class, new PaginatedRestQueryMock());

        Test.startTest();
        List<Object> rows = ToolingApiRestClient.query('SELECT MetadataComponentName FROM MetadataComponentDependency');
        Test.stopTest();

        System.assertEquals(2, rows.size());
        System.assertEquals('Account_Priority_Flow', (String) ((Map<String, Object>) rows[0]).get('MetadataComponentName'));
        System.assertEquals('Account_Score_Flow', (String) ((Map<String, Object>) rows[1]).get('MetadataComponentName'));
    }

    @isTest
    static void testBuildEndpoint_usesNamedCredentialAlias() {
        System.assertEquals(
            'callout:Tooling_NC/services/data/v60.0/tooling/query?q=SELECT+Id+FROM+Account',
            ToolingApiRestClient.buildEndpoint(
                '/services/data/v60.0/tooling/query?q=SELECT+Id+FROM+Account'
            )
        );
    }

    @isTest
    static void testBuildNamedCredentialGuidance_mentionsSetup() {
        String message = ToolingApiRestClient.buildNamedCredentialGuidance('missing credential');
        System.assert(message.contains('Tooling_NC'));
        System.assert(message.contains('Named Credential'));
        System.assert(message.contains('missing credential'));
    }

    private class PaginatedRestQueryMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');

            if (req.getEndpoint().contains('/tooling/query/')) {
                res.setBody(ToolingApiMocks.buildRestQueryResponse(
                    new List<Object>{
                        new Map<String, Object>{ 'MetadataComponentName' => 'Account_Score_Flow' }
                    },
                    true,
                    null
                ));
                return res;
            }

            res.setBody(ToolingApiMocks.buildRestQueryResponse(
                new List<Object>{
                    new Map<String, Object>{ 'MetadataComponentName' => 'Account_Priority_Flow' }
                },
                false,
                '/services/data/v60.0/tooling/query/01gxx0000000001AAA-2000'
            ));
            return res;
        }
    }
}

@isTest
private class ReportTypeMetadataClientTest {

    @isTest
    static void testListMetadataFullNames_parsesResults() {
        Test.setMock(HttpCalloutMock.class, new ReportTypeMetadataSoapMock());

        Test.startTest();
        List<String> fullNames = ReportTypeMetadataClient.listMetadataFullNames('ReportType');
        Test.stopTest();

        System.assertEquals(2, fullNames.size());
        System.assertEquals('Account_Custom', fullNames[0]);
        System.assertEquals('Opportunity_Custom', fullNames[1]);
    }

    @isTest
    static void testReadReportTypes_parsesColumns() {
        Test.setMock(HttpCalloutMock.class, new ReportTypeMetadataSoapMock());

        Test.startTest();
        List<ReportTypeMetadataClient.ReportTypeRecord> records =
            ReportTypeMetadataClient.readReportTypes(new List<String>{ 'Account_Custom' });
        Test.stopTest();

        System.assertEquals(1, records.size());
        System.assertEquals('Account_Custom', records[0].fullName);
        System.assertEquals('Account Custom', records[0].label);
        System.assertEquals('Account', records[0].baseObject);
        System.assertEquals(2, records[0].columnReferences.size());
        System.assertEquals('Account', records[0].columnReferences[0].tableName);
        System.assertEquals('Priority__c', records[0].columnReferences[0].fieldName);
    }

    @isTest
    static void testListReportTypes_batchesReadRequests() {
        Test.setMock(HttpCalloutMock.class, new ReportTypeMetadataSoapMock());

        Test.startTest();
        List<ReportTypeMetadataClient.ReportTypeRecord> records = ReportTypeMetadataClient.listReportTypes();
        Test.stopTest();

        System.assertEquals(2, records.size());
    }

    private class ReportTypeMetadataSoapMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String requestBody = req.getBody();

            if (requestBody.contains('<urn:listMetadata')) {
                res.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata">' +
                    '<soapenv:Body><listMetadataResponse>' +
                    '<result><fullName>Account_Custom</fullName></result>' +
                    '<result><fullName>Opportunity_Custom</fullName></result>' +
                    '</listMetadataResponse></soapenv:Body></soapenv:Envelope>'
                );
                return res;
            }

            if (requestBody.contains('<urn:fullNames>Opportunity_Custom</urn:fullNames>')) {
                res.setBody(
                    '<?xml version="1.0" encoding="UTF-8"?>' +
                    '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                    '<soapenv:Body><readMetadataResponse><result>' +
                    '<records xsi:type="ReportType">' +
                    '<fullName>Account_Custom</fullName><baseObject>Account</baseObject><label>Account Custom</label>' +
                    '<sections><columns><table>Account</table><field>Priority__c</field></columns></sections>' +
                    '</records>' +
                    '<records xsi:type="ReportType">' +
                    '<fullName>Opportunity_Custom</fullName><baseObject>Opportunity</baseObject><label>Opportunity Custom</label>' +
                    '<sections><columns><table>Opportunity</table><field>Amount</field></columns></sections>' +
                    '</records>' +
                    '</result></readMetadataResponse></soapenv:Body></soapenv:Envelope>'
                );
                return res;
            }

            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                '<soapenv:Body><readMetadataResponse><result>' +
                '<records xsi:type="ReportType">' +
                '<fullName>Account_Custom</fullName><baseObject>Account</baseObject><label>Account Custom</label>' +
                '<sections>' +
                '<columns><table>Account</table><field>Priority__c</field></columns>' +
                '<columns><table>Account</table><field>Score__c</field></columns>' +
                '</sections>' +
                '</records>' +
                '</result></readMetadataResponse></soapenv:Body></soapenv:Envelope>'
            );
            return res;
        }
    }
}

/**
 * ToolingApiMocks
 * ------------------
 * Shared HttpCalloutMock implementations for Part 2 test classes, so
 * Tooling REST / SOAP and Metadata SOAP callouts can be unit tested deterministically
 * without live org metadata.
 */
@isTest
public class ToolingApiMocks {

    /** Returns a single MetadataComponentDependency-style row referencing a Flow. */
    public class DependencySuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            String fieldComponentId = findFieldComponentId('Account', 'Score__c');
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(buildRestQueryResponse(new List<Object>{
                new Map<String, Object>{
                    'MetadataComponentType' => 'Flow',
                    'MetadataComponentName' => 'Account_After_Update',
                    'RefMetadataComponentId' => fieldComponentId,
                    'RefMetadataComponentType' => 'CustomField'
                }
            }));
            return res;
        }
    }

    /** Returns an empty result set - used to test the "no usages found" path. */
    public class EmptyResultMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(buildRestQueryResponse(new List<Object>()));
            return res;
        }
    }

    /** Simulates a Tooling API failure (e.g. auth error / timeout). */
    public class FailureMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setBody('Internal Server Error');
            return res;
        }
    }

    /** Simulates a Tooling SOAP invalid session fault. */
    public class InvalidSessionMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(500);
            res.setHeader('Content-Type', 'text/xml');
            res.setBody(
                '<?xml version="1.0" encoding="UTF-8"?>' +
                '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
                'xmlns:sf="urn:fault.tooling.soap.sforce.com" ' +
                'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">' +
                '<soapenv:Body>' +
                '<soapenv:Fault>' +
                '<faultcode>sf:INVALID_SESSION_ID</faultcode>' +
                '<faultstring>INVALID_SESSION_ID: This session is not valid for use with the API</faultstring>' +
                '<detail><sf:UnexpectedErrorFault xsi:type="sf:UnexpectedErrorFault">' +
                '<sf:exceptionCode>INVALID_SESSION_ID</sf:exceptionCode>' +
                '<sf:exceptionMessage>This session is not valid for use with the API</sf:exceptionMessage>' +
                '</sf:UnexpectedErrorFault></detail>' +
                '</soapenv:Fault>' +
                '</soapenv:Body>' +
                '</soapenv:Envelope>'
            );
            return res;
        }
    }

    /** Returns a ReportType row whose metadata JSON references the given field/object. */
    public class ReportTypeSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'text/xml');
            res.setBody(buildSoapQueryResponse(new List<Object>{
                new Map<String, Object>{
                    'DeveloperName' => 'Accounts_and_Scores',
                    'Metadata' => new Map<String, Object>{
                        'baseObject' => 'account',
                        'sections' => 'includes score__c column'
                    }
                }
            }));
            return res;
        }
    }

    /** Returns a Report row whose metadata references the given field/object. */
    public class ReportSuccessMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'text/xml');
            res.setBody(buildSoapQueryResponse(new List<Object>{
                new Map<String, Object>{
                    'DeveloperName' => 'Account_Priority_Report',
                    'Name' => 'Account Priority Report',
                    'Metadata' => new Map<String, Object>{
                        'reportType' => 'Account',
                        'detailColumns' => new List<Object>{ 'ACCOUNT.PRIORITY__C' }
                    }
                }
            }));
            return res;
        }
    }

    @TestVisible
    private static String findFieldComponentId(String objectApiName, String fieldApiName) {
        Map<String, String> byId = ToolingDependencyUsageProvider.resolveFieldComponentIds(
            objectApiName,
            new List<String>{ fieldApiName }
        );
        for (String componentId : byId.keySet()) {
            return componentId;
        }
        return null;
    }

    @TestVisible
    private static String buildSoapQueryResponse(List<Object> records) {
        String recordsXml = '';
        for (Object recordObj : records) {
            recordsXml += '<records xsi:type="sf:sObject">' + objectToXml(recordObj) + '</records>';
        }

        return
            '<?xml version="1.0" encoding="UTF-8"?>' +
            '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" ' +
            'xmlns="urn:tooling.soap.sforce.com" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
            'xmlns:sf="urn:sobject.tooling.soap.sforce.com">' +
            '<soapenv:Body>' +
            '<queryResponse>' +
            '<result>' +
            '<done>true</done>' +
            '<size>' + records.size() + '</size>' +
            '<totalSize>' + records.size() + '</totalSize>' +
            recordsXml +
            '</result>' +
            '</queryResponse>' +
            '</soapenv:Body>' +
            '</soapenv:Envelope>';
    }

    @TestVisible
    private static String buildRestQueryResponse(List<Object> records) {
        return buildRestQueryResponse(records, true, null);
    }

    @TestVisible
    private static String buildRestQueryResponse(List<Object> records, Boolean done, String nextRecordsUrl) {
        Map<String, Object> payload = new Map<String, Object>{
            'totalSize' => records == null ? 0 : records.size(),
            'done' => done,
            'records' => records == null ? new List<Object>() : records
        };
        if (!String.isBlank(nextRecordsUrl)) {
            payload.put('nextRecordsUrl', nextRecordsUrl);
        }
        return JSON.serialize(payload);
    }

    private static String objectToXml(Object value) {
        if (value == null) {
            return '';
        }
        if (value instanceof Map<String, Object>) {
            String xml = '';
            for (String key : ((Map<String, Object>) value).keySet()) {
                Object childValue = ((Map<String, Object>) value).get(key);
                if (childValue instanceof List<Object>) {
                    for (Object listValue : (List<Object>) childValue) {
                        xml += '<' + key + '>' + objectToXml(listValue) + '</' + key + '>';
                    }
                } else {
                    xml += '<' + key + '>' + objectToXml(childValue) + '</' + key + '>';
                }
            }
            return xml;
        }
        return escapeXml(String.valueOf(value));
    }

    private static String escapeXml(String value) {
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }
}
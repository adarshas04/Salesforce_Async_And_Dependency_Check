public with sharing class ToolingApiRestClient {

    @TestVisible
    private static final String NAMED_CREDENTIAL = 'Tooling_NC';
    private static final String API_VERSION = '60.0';
    private static final Integer TIMEOUT_MS = 30000;

    public static List<Object> query(String toolingSoql) {
        RestQueryResult page = executeGet(
            '/services/data/v' + API_VERSION + '/tooling/query?q=' +
            EncodingUtil.urlEncode(toolingSoql, 'UTF-8')
        );

        List<Object> allRecords = new List<Object>();
        allRecords.addAll(page.records);

        while (!page.done && !String.isBlank(page.nextRecordsUrl)) {
            page = executeGet(page.nextRecordsUrl);
            allRecords.addAll(page.records);
        }

        return allRecords;
    }

    @TestVisible
    private static RestQueryResult parseQueryResponse(String responseBody) {
        if (String.isBlank(responseBody)) {
            throw new ToolingApiException('Tooling REST response body was empty.');
        }

        Object parsed = JSON.deserializeUntyped(responseBody);
        if (!(parsed instanceof Map<String, Object>)) {
            throw new ToolingApiException('Tooling REST response was not a JSON object.');
        }

        Map<String, Object> payload = (Map<String, Object>) parsed;
        RestQueryResult result = new RestQueryResult();

        Object recordsValue = payload.get('records');
        if (recordsValue instanceof List<Object>) {
            result.records.addAll((List<Object>) recordsValue);
        }

        Object doneValue = payload.get('done');
        if (doneValue instanceof Boolean) {
            result.done = (Boolean) doneValue;
        }

        Object nextRecordsUrlValue = payload.get('nextRecordsUrl');
        if (nextRecordsUrlValue instanceof String) {
            result.nextRecordsUrl = (String) nextRecordsUrlValue;
        }

        return result;
    }

    private static RestQueryResult executeGet(String relativeUrl) {
        HttpRequest request = new HttpRequest();
        request.setEndpoint(buildEndpoint(relativeUrl));
        request.setMethod('GET');
        request.setHeader('Accept', 'application/json');
        request.setTimeout(TIMEOUT_MS);

        try {
            HttpResponse response = new Http().send(request);
            if (response.getStatusCode() >= 200 && response.getStatusCode() < 300) {
                return parseQueryResponse(response.getBody());
            }

            throw new ToolingApiException(
                'Tooling REST query failed [' + response.getStatusCode() + ']: ' + response.getBody()
            );
        } catch (ToolingApiException ex) {
            throw ex;
        } catch (Exception ex) {
            throw new ToolingApiException(buildNamedCredentialGuidance(ex.getMessage()));
        }
    }

    @TestVisible
    private static String buildEndpoint(String relativeUrl) {
        String normalizedUrl = String.isBlank(relativeUrl) ? '' : relativeUrl.trim();
        if (!normalizedUrl.startsWith('/')) {
            normalizedUrl = '/' + normalizedUrl;
        }
        return 'callout:' + NAMED_CREDENTIAL + normalizedUrl;
    }

    @TestVisible
    private static String buildNamedCredentialGuidance(String originalMessage) {
        return
            'Tooling REST callout failed. Configure the "' + NAMED_CREDENTIAL +
            '" Named Credential to point to your Salesforce org base URL with an OAuth identity. Original error: ' +
            originalMessage;
    }

    private class RestQueryResult {
        private List<Object> records = new List<Object>();
        private Boolean done = true;
        private String nextRecordsUrl;
    }

    public class ToolingApiException extends Exception {}
}

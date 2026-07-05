public with sharing class ReportTypeMetadataClient {

    private static final String API_VERSION = '60.0';
    private static final Integer READ_BATCH_SIZE = 10;
    private static final String METADATA_NS = 'http://soap.sforce.com/2006/04/metadata';

    public static List<ReportTypeRecord> listReportTypes() {
        List<String> fullNames = listMetadataFullNames('ReportType');
        if (fullNames.isEmpty()) {
            return new List<ReportTypeRecord>();
        }

        List<ReportTypeRecord> records = new List<ReportTypeRecord>();
        for (Integer startIndex = 0; startIndex < fullNames.size(); startIndex += READ_BATCH_SIZE) {
            Integer endIndex = Math.min(fullNames.size(), startIndex + READ_BATCH_SIZE);
            List<String> batchFullNames = new List<String>();
            for (Integer index = startIndex; index < endIndex; index++) {
                batchFullNames.add(fullNames[index]);
            }
            records.addAll(readReportTypes(batchFullNames));
        }
        return records;
    }

    @TestVisible
    private static List<String> listMetadataFullNames(String metadataType) {
        Dom.XmlNode responseBody = invokeMetadataOperation(
            'listMetadata',
            '<urn:listMetadata xmlns:urn="' + METADATA_NS + '">' +
                '<urn:queries><urn:type>' + escapeXml(metadataType) + '</urn:type></urn:queries>' +
                '<urn:asOfVersion>' + API_VERSION + '</urn:asOfVersion>' +
            '</urn:listMetadata>'
        );

        Dom.XmlNode responseNode = getFirstChildByLocalName(responseBody, 'listMetadataResponse');
        List<String> fullNames = new List<String>();
        if (responseNode == null) {
            return fullNames;
        }

        for (Dom.XmlNode resultNode : responseNode.getChildElements()) {
            if (getLocalName(resultNode) != 'result') {
                continue;
            }
            Dom.XmlNode fullNameNode = getFirstChildByLocalName(resultNode, 'fullName');
            if (fullNameNode != null && !String.isBlank(fullNameNode.getText())) {
                fullNames.add(fullNameNode.getText());
            }
        }
        return fullNames;
    }

    @TestVisible
    private static List<ReportTypeRecord> readReportTypes(List<String> fullNames) {
        if (fullNames == null || fullNames.isEmpty()) {
            return new List<ReportTypeRecord>();
        }

        List<String> fullNameElements = new List<String>();
        for (String fullName : fullNames) {
            fullNameElements.add('<urn:fullNames>' + escapeXml(fullName) + '</urn:fullNames>');
        }

        Dom.XmlNode responseBody = invokeMetadataOperation(
            'readMetadata',
            '<urn:readMetadata xmlns:urn="' + METADATA_NS + '">' +
                '<urn:type>ReportType</urn:type>' +
                String.join(fullNameElements, '') +
            '</urn:readMetadata>'
        );

        Dom.XmlNode responseNode = getFirstChildByLocalName(responseBody, 'readMetadataResponse');
        Dom.XmlNode resultNode = responseNode == null ? null : getFirstChildByLocalName(responseNode, 'result');
        if (resultNode == null) {
            return new List<ReportTypeRecord>();
        }

        List<ReportTypeRecord> records = new List<ReportTypeRecord>();
        for (Dom.XmlNode recordNode : resultNode.getChildElements()) {
            if (getLocalName(recordNode) != 'records') {
                continue;
            }
            records.add(parseReportTypeRecord(recordNode));
        }
        return records;
    }

    @TestVisible
    private static ReportTypeRecord parseReportTypeRecord(Dom.XmlNode recordNode) {
        ReportTypeRecord record = new ReportTypeRecord();
        for (Dom.XmlNode childNode : recordNode.getChildElements()) {
            String localName = getLocalName(childNode);
            if (localName == 'fullName') {
                record.fullName = childNode.getText();
            } else if (localName == 'label') {
                record.label = childNode.getText();
            } else if (localName == 'baseObject') {
                record.baseObject = childNode.getText();
            } else if (localName == 'sections') {
                record.columnReferences.addAll(extractColumnReferences(childNode));
            }
        }
        return record;
    }

    private static List<ColumnReference> extractColumnReferences(Dom.XmlNode sectionNode) {
        List<ColumnReference> columnReferences = new List<ColumnReference>();
        for (Dom.XmlNode childNode : sectionNode.getChildElements()) {
            if (getLocalName(childNode) != 'columns') {
                continue;
            }

            String tableName;
            String fieldName;
            for (Dom.XmlNode columnChild : childNode.getChildElements()) {
                String localName = getLocalName(columnChild);
                if (localName == 'table') {
                    tableName = columnChild.getText();
                } else if (localName == 'field') {
                    fieldName = columnChild.getText();
                }
            }

            if (!String.isBlank(tableName) && !String.isBlank(fieldName)) {
                columnReferences.add(new ColumnReference(tableName, fieldName));
            }
        }
        return columnReferences;
    }

    private static Dom.XmlNode invokeMetadataOperation(String operationName, String bodyContent) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + '/services/Soap/m/' + API_VERSION);
        req.setMethod('POST');
        req.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        req.setHeader('SOAPAction', operationName);
        req.setBody(wrapMetadataEnvelope(bodyContent));
        req.setTimeout(30000);

        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (Exception ex) {
            throw new MetadataApiException('Metadata API callout failed: ' + ex.getMessage());
        }

        if (res.getStatusCode() != 200) {
            throw new MetadataApiException(
                'Metadata API call failed [' + res.getStatusCode() + ']: ' + res.getBody()
            );
        }

        Dom.Document document = new Dom.Document();
        document.load(res.getBody());

        Dom.XmlNode envelopeNode = document.getRootElement();
        Dom.XmlNode soapBodyNode = getFirstChildByLocalName(envelopeNode, 'Body');
        if (soapBodyNode == null) {
            throw new MetadataApiException('Metadata SOAP response did not contain a Body element.');
        }

        Dom.XmlNode faultNode = getFirstChildByLocalName(soapBodyNode, 'Fault');
        if (faultNode != null) {
            Dom.XmlNode faultStringNode = getFirstChildByLocalName(faultNode, 'faultstring');
            throw new MetadataApiException(
                'Metadata SOAP fault: ' + (faultStringNode == null ? 'Unknown fault' : faultStringNode.getText())
            );
        }

        return soapBodyNode;
    }

    private static Dom.XmlNode getFirstChildByLocalName(Dom.XmlNode parentNode, String localName) {
        for (Dom.XmlNode childNode : parentNode.getChildElements()) {
            if (getLocalName(childNode) == localName) {
                return childNode;
            }
        }
        return null;
    }

    private static String getLocalName(Dom.XmlNode node) {
        String nodeName = node.getName();
        Integer separatorIndex = nodeName.indexOf(':');
        return separatorIndex >= 0 ? nodeName.substring(separatorIndex + 1) : nodeName;
    }

    private static String escapeXml(String value) {
        if (value == null) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;');
    }

    private static String wrapMetadataEnvelope(String bodyContent) {
        return
            '<?xml version="1.0" encoding="utf-8"?>' +
            '<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema" ' +
            'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
            'xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">' +
            '<env:Header>' +
            '<urn:SessionHeader xmlns:urn="' + METADATA_NS + '">' +
            '<urn:sessionId>' + escapeXml(UserInfo.getSessionId()) + '</urn:sessionId>' +
            '</urn:SessionHeader>' +
            '</env:Header>' +
            '<env:Body>' +
            bodyContent +
            '</env:Body>' +
            '</env:Envelope>';
    }

    public class ReportTypeRecord {
        public String fullName;
        public String label;
        public String baseObject;
        public List<ColumnReference> columnReferences = new List<ColumnReference>();
    }

    public class ColumnReference {
        public String tableName;
        public String fieldName;

        public ColumnReference(String tableName, String fieldName) {
            this.tableName = tableName;
            this.fieldName = fieldName;
        }
    }

    public class MetadataApiException extends Exception {}
}

public interface IMetadataUsageProvider {
    List<FieldUsageAnalyzerService.UsageResult> findUsages(
        String objectApiName,
        List<String> fieldApiNames
    );
    String getCategoryKey();
}

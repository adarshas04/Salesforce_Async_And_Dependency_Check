public with sharing class AccountScoreAndEscalationLauncher {

    public static final Integer DEFAULT_BATCH_SCOPE_SIZE = 200;
    public static final Integer PLATFORM_MAX_BATCH_SCOPE_SIZE = 2000;

    public static Id launch(Set<Id> accountIds) {
        return launch(accountIds, DEFAULT_BATCH_SCOPE_SIZE);
    }

    public static Id launch(Set<Id> accountIds, Integer batchScopeSize) {
        Set<Id> normalizedAccountIds = normalizeAccountIds(accountIds);
        if (normalizedAccountIds.isEmpty()) {
            throw new IllegalArgumentException('No Account Ids supplied to AccountScoreAndEscalationLauncher.');
        }

        validateBatchScopeSize(batchScopeSize);

        AccountScoreAndEscalationBatch batch = new AccountScoreAndEscalationBatch(normalizedAccountIds);
        return Database.executeBatch(batch, batchScopeSize);
    }

    @InvocableMethod(
        label='Launch Account Score And Escalation Refresh'
        description='Accepts Account Ids and kicks off async score recalculation and escalation flag evaluation.'
        category='Account Processing'
    )
    public static List<LaunchResult> launchFromFlow(List<LaunchRequest> requests) {
        List<LaunchResult> results = new List<LaunchResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        Set<Id> combinedAccountIds = new Set<Id>();
        List<Boolean> requestIsValid = new List<Boolean>();

        for (LaunchRequest req : requests) {
            LaunchResult res = new LaunchResult();
            try {
                combinedAccountIds.addAll(parseAccountIds(req));
                requestIsValid.add(true);
            } catch (Exception ex) {
                res.errorMessage = ex.getMessage();
                requestIsValid.add(false);
            }
            results.add(res);
        }

        Id jobId;
        if (!combinedAccountIds.isEmpty()) {
            jobId = launch(combinedAccountIds, DEFAULT_BATCH_SCOPE_SIZE);
        }

        for (Integer i = 0; i < results.size(); i++) {
            if (requestIsValid[i] && jobId != null) {
                results[i].success = true;
                results[i].jobId = jobId;
            } else if (!requestIsValid[i]) {
                results[i].success = false;
            } else {
                results[i].success = false;
                results[i].errorMessage = 'No valid Account Ids were supplied.';
            }
        }

        return results;
    }

    private static void validateBatchScopeSize(Integer batchScopeSize) {
        if (batchScopeSize == null || batchScopeSize <= 0 || batchScopeSize > PLATFORM_MAX_BATCH_SCOPE_SIZE) {
            throw new IllegalArgumentException(
                'Batch scope size must be between 1 and ' + PLATFORM_MAX_BATCH_SCOPE_SIZE + '.'
            );
        }
    }

    private static Set<Id> normalizeAccountIds(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            return new Set<Id>();
        }

        Set<Id> normalizedAccountIds = new Set<Id>();
        for (Id accountId : accountIds) {
            validateAccountId(accountId);
            normalizedAccountIds.add(accountId);
        }
        return normalizedAccountIds;
    }

    private static Set<Id> parseAccountIds(LaunchRequest req) {
        if (req == null || req.accountIds == null || req.accountIds.isEmpty()) {
            throw new IllegalArgumentException('Each request must include at least one Account Id.');
        }

        Set<Id> ids = new Set<Id>();
        for (String accountIdValue : req.accountIds) {
            Id accountId;
            try {
                accountId = Id.valueOf(accountIdValue);
            } catch (Exception ex) {
                throw new IllegalArgumentException('Invalid Salesforce Id supplied: ' + accountIdValue + '.');
            }

            validateAccountId(accountId);
            ids.add(accountId);
        }
        return ids;
    }

    private static void validateAccountId(Id accountId) {
        if (accountId == null) {
            throw new IllegalArgumentException('Null Account Id supplied to AccountScoreAndEscalationLauncher.');
        }
        if (accountId.getSObjectType() != Account.SObjectType) {
            throw new IllegalArgumentException('Only Account Ids may be supplied to AccountScoreAndEscalationLauncher.');
        }
    }

    public class LaunchRequest {
        @InvocableVariable(required=true label='Account Ids')
        public List<String> accountIds;
    }

    public class LaunchResult {
        @InvocableVariable public Boolean success;
        @InvocableVariable public Id jobId;
        @InvocableVariable public String errorMessage;
    }
}

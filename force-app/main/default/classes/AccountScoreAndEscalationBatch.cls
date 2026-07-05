public with sharing class AccountScoreAndEscalationBatch implements Database.Batchable<sObject>, Database.Stateful {

    private Set<Id> accountIds;

    public Integer totalProcessed = 0;
    public Integer totalFlagged = 0;
    public Integer totalErrors = 0;
    public List<String> errorMessages = new List<String>();

    public AccountScoreAndEscalationBatch(Set<Id> accountIds) {
        if (accountIds == null || accountIds.isEmpty()) {
            throw new IllegalArgumentException('AccountScoreAndEscalationBatch requires a non-empty set of Account Ids.');
        }
        this.accountIds = accountIds;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([
            SELECT Id, Priority__c, Score__c, Escalation_Flag__c
            FROM Account
            WHERE Id IN :accountIds
        ]);
    }

    public void execute(Database.BatchableContext bc, List<Account> scope) {
        try {
            AccountScoreAndEscalationService scoringService = new AccountScoreAndEscalationService();
            Map<Id, Account> accountsById = new Map<Id, Account>(scope);

            // We only need rollups here, not full opp rows.
            Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary> oppSummaryByAccountId =
                new Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary>();
            for (AggregateResult row : [
                SELECT AccountId accountId,
                       COUNT(Id) openOppCount,
                       SUM(Amount) openOppAmount,
                       MIN(CreatedDate) oldestOpenCreatedDate
                FROM Opportunity
                WHERE AccountId IN :accountsById.keySet()
                AND IsClosed = false
                GROUP BY AccountId
            ]) {
                AccountScoreAndEscalationService.OpenOpportunitySummary summary =
                    new AccountScoreAndEscalationService.OpenOpportunitySummary();
                summary.openOpportunityCount = Integer.valueOf(String.valueOf(row.get('openOppCount')));
                summary.openOpportunityAmount = row.get('openOppAmount') == null
                    ? 0
                    : (Decimal) row.get('openOppAmount');
                summary.oldestOpenOpportunityCreatedDate =
                    (Datetime) row.get('oldestOpenCreatedDate');
                oppSummaryByAccountId.put((Id) row.get('accountId'), summary);
            }

            AccountScoreAndEscalationService.ProcessResult result =
                scoringService.process(accountsById, oppSummaryByAccountId);

            if (!result.accountsToUpdate.isEmpty()) {
                List<Database.SaveResult> srs = Database.update(result.accountsToUpdate, false);
                for (Database.SaveResult sr : srs) {
                    if (sr.isSuccess()) {
                        totalProcessed++;
                        if (result.flaggedAccountIds.contains(sr.getId())) {
                            totalFlagged++;
                        }
                    } else {
                        totalErrors++;
                        for (Database.Error e : sr.getErrors()) {
                            recordError(sr.getId() + ': ' + e.getMessage());
                        }
                    }
                }
            }

        } catch (Exception ex) {
            totalErrors++;
            recordError('Batch execute exception: ' + ex.getMessage());
        }
    }

    public void finish(Database.BatchableContext bc) {
        System.debug(LoggingLevel.INFO,
            'AccountScoreAndEscalationBatch finished. Processed=' + totalProcessed +
            ' Flagged=' + totalFlagged +
            ' Errors=' + totalErrors);

        if (totalErrors > 0) {
            System.debug(LoggingLevel.WARN, 'Sample errors: ' + errorMessages[0]);
            // We can log on a custom object/use nebula if present - for error logs/choose a notification method as well.
        }
    }

    private void recordError(String message) {
        errorMessages.add(message);
    }
}

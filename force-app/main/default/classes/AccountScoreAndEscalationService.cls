/**
 * AccountScoreAndEscalationService
 * ----------------------
 * Contains the business rules for:
 *   1. Recalculating Account.Score__c based on external signal data.
 *   2. Determining escalation eligibility (High Priority Account + an
 *      Opportunity that has been open > 45 days).
 *
 * Kept separate from the batch class (AccountScoreAndEscalationBatch)
 * so the rules can be unit tested in isolation and reused from other entry
 * points (triggers, invocable actions, LWC controllers, etc.)
 */
public with sharing class AccountScoreAndEscalationService {

    // Threshold for Opportunity's age in days
    public static final Integer ESCALATION_THRESHOLD_DAYS = 45;
    public static final String HIGH_PRIORITY_VALUE = 'High Priority';

    public Decimal calculateScore(Account acc, OpenOpportunitySummary oppSummary) {
        Decimal score = 0;

        // Sample scoring criteria
        Integer openOppCount = oppSummary == null ? 0 : oppSummary.openOpportunityCount;
        Decimal openAmount = oppSummary == null ? 0 : oppSummary.openOpportunityAmount;

        score += openOppCount * 5;
        score += (openAmount / 1000);
        if (acc.Priority__c == HIGH_PRIORITY_VALUE) {
            score += 20;
        }

        return score.setScale(2);
    }

    public Boolean isEscalationEligible(Account acc, OpenOpportunitySummary oppSummary) {
        if (acc.Priority__c != HIGH_PRIORITY_VALUE) {
            return false;
        }
        if (oppSummary == null || oppSummary.oldestOpenOpportunityCreatedDate == null) {
            return false;
        }
        Date cutoff = Date.today().addDays(-ESCALATION_THRESHOLD_DAYS);
        return oppSummary.oldestOpenOpportunityCreatedDate.date() <= cutoff;
    }

    /**
     * Bulk-safe helper: given a map of AccountId -> Account and
     * AccountId -> summarized open Opportunity metrics, returns the
     * Account updates needed for score recalculation and flagging.
     */
    public ProcessResult process(Map<Id, Account> accountsById,
                                 Map<Id, OpenOpportunitySummary> oppSummaryByAccountId) {
        ProcessResult result = new ProcessResult();

        for (Account acc : accountsById.values()) {
            OpenOpportunitySummary oppSummary = oppSummaryByAccountId.containsKey(acc.Id)
                ? oppSummaryByAccountId.get(acc.Id)
                : new OpenOpportunitySummary();

            Account toUpdate = new Account(Id = acc.Id);
            Boolean isEligible = isEscalationEligible(acc, oppSummary);

            toUpdate.Score__c = calculateScore(acc, oppSummary);
            toUpdate.Escalation_Flag__c = isEligible;
            result.accountsToUpdate.add(toUpdate);

            if (isEligible) {
                result.flaggedAccountIds.add(acc.Id);
            }
        }
        return result;
    }

    public class OpenOpportunitySummary {
        public Integer openOpportunityCount = 0;
        public Decimal openOpportunityAmount = 0;
        public Datetime oldestOpenOpportunityCreatedDate;
    }

    public class ProcessResult {
        public List<Account> accountsToUpdate = new List<Account>();
        public Set<Id> flaggedAccountIds = new Set<Id>();
    }
}

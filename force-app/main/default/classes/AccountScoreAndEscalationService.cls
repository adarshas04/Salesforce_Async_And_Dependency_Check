public with sharing class AccountScoreAndEscalationService {

    public static final Integer ESCALATION_THRESHOLD_DAYS = 45;
    public static final String HIGH_PRIORITY_VALUE = 'High Priority';

    public Decimal calculateScore(Account acc, OpenOpportunitySummary oppSummary) {
        Decimal score = 0;

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
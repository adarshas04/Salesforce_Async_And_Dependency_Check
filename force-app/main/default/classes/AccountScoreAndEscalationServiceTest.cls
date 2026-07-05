@isTest
private class AccountScoreAndEscalationServiceTest {
    private static AccountScoreAndEscalationService.OpenOpportunitySummary buildSummary(List<Opportunity> relatedOpps) {
        AccountScoreAndEscalationService.OpenOpportunitySummary summary = new AccountScoreAndEscalationService.OpenOpportunitySummary();
        if (relatedOpps == null) {
            return summary;
        }

        for (Opportunity opp : relatedOpps) {
            if (opp.IsClosed) {
                continue;
            }

            summary.openOpportunityCount++;
            summary.openOpportunityAmount += (opp.Amount == null ? 0 : opp.Amount);
            if (opp.CreatedDate != null &&
                (summary.oldestOpenOpportunityCreatedDate == null ||
                 opp.CreatedDate < summary.oldestOpenOpportunityCreatedDate)) {
                summary.oldestOpenOpportunityCreatedDate = opp.CreatedDate;
            }
        }
        return summary;
    }

    @isTest
    static void testCalculateScore_highPriorityWithOpenOpps() {
        Account acc = new Account(Name = 'Test HP', Priority__c = 'High Priority');
        insert acc;

        List<Opportunity> opps = new List<Opportunity>{
            new Opportunity(Name = 'Opp1', AccountId = acc.Id, StageName = 'Prospecting',
                             CloseDate = Date.today().addDays(30), Amount = 10000),
            new Opportunity(Name = 'Opp2', AccountId = acc.Id, StageName = 'Prospecting',
                             CloseDate = Date.today().addDays(30), Amount = 5000)
        };

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        Decimal score = svc.calculateScore(
            acc,
            buildSummary(opps)
        );

        // 2 open opps * 5 = 10, + (15000/1000) = 15, + 20 (high priority) = 45
        System.assertEquals(45.00, score, 'Score calculation should match expected weighting.');
    }

    @isTest
    static void testCalculateScore_noOpps() {
        Account acc = new Account(Name = 'Test No Opp', Priority__c = 'Standard');
        insert acc;

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        Decimal score = svc.calculateScore(
            acc,
            buildSummary(new List<Opportunity>())
        );
        System.assertEquals(0.00, score, 'Score should be zero with no opps and standard priority.');
    }

    @isTest
    static void testIsEscalationEligible_true() {
        Account acc = new Account(Name = 'Test Escalate', Priority__c = 'High Priority');
        insert acc;

        Opportunity agedOpp = new Opportunity(
            Name = 'Aged Opp', AccountId = acc.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert agedOpp;
        // Backdate CreatedDate is not directly settable via DML; simulate via
        // Test.setCreatedDate for deterministic aging in tests.
        Test.setCreatedDate(agedOpp.Id, DateTime.now().addDays(-50));

        agedOpp = [SELECT Id, AccountId, IsClosed, CreatedDate, Amount FROM Opportunity WHERE Id = :agedOpp.Id];

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        Boolean eligible = svc.isEscalationEligible(
            acc,
            buildSummary(new List<Opportunity>{ agedOpp })
        );
        System.assertEquals(true, eligible, 'High priority account with a >45 day open opp should be escalation eligible.');
    }

    @isTest
    static void testIsEscalationEligible_falseWhenNotHighPriority() {
        Account acc = new Account(Name = 'Test Std', Priority__c = 'Standard');
        insert acc;

        Opportunity opp = new Opportunity(
            Name = 'Opp', AccountId = acc.Id, StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert opp;

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        Boolean eligible = svc.isEscalationEligible(
            acc,
            buildSummary(new List<Opportunity>{ opp })
        );
        System.assertEquals(false, eligible, 'Non-high-priority accounts should never be escalation eligible.');
    }

    @isTest
    static void testProcess_bulkWrapper() {
        Account acc = new Account(Name = 'Bulk Test', Priority__c = 'High Priority');
        insert acc;

        Map<Id, Account> accountsById = new Map<Id, Account>{ acc.Id => acc };
        Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary> oppSummaryByAccountId =
            new Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary>{
                acc.Id => new AccountScoreAndEscalationService.OpenOpportunitySummary()
            };

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        AccountScoreAndEscalationService.ProcessResult result = svc.process(accountsById, oppSummaryByAccountId);

        System.assertEquals(1, result.accountsToUpdate.size());
        System.assertEquals(0, result.flaggedAccountIds.size(), 'No open aged opps, so no escalation flag expected.');
        System.assertEquals(false, result.accountsToUpdate[0].Escalation_Flag__c);
    }

    @isTest
    static void testProcess_setsAndClearsAccountEscalationFields() {
        Account acc = new Account(Name = 'Flagged Account', Priority__c = 'High Priority');
        insert acc;

        Opportunity agedOpp = new Opportunity(
            Name = 'Flagged Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(10)
        );
        insert agedOpp;
        Test.setCreatedDate(agedOpp.Id, DateTime.now().addDays(-60));

        agedOpp = [
            SELECT Id, AccountId, IsClosed, CreatedDate, Amount
            FROM Opportunity
            WHERE Id = :agedOpp.Id
        ];

        Map<Id, Account> accountsById = new Map<Id, Account>{ acc.Id => acc };
        Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary> oppSummaryByAccountId =
            new Map<Id, AccountScoreAndEscalationService.OpenOpportunitySummary>{
                acc.Id => buildSummary(new List<Opportunity>{ agedOpp })
            };

        AccountScoreAndEscalationService svc = new AccountScoreAndEscalationService();
        AccountScoreAndEscalationService.ProcessResult result = svc.process(accountsById, oppSummaryByAccountId);

        System.assertEquals(1, result.accountsToUpdate.size());
        System.assertEquals(
            true,
            result.accountsToUpdate[0].Escalation_Flag__c,
            'The Account should be flagged when the rule matches.'
        );
        System.assertEquals(1, result.flaggedAccountIds.size());
    }
}
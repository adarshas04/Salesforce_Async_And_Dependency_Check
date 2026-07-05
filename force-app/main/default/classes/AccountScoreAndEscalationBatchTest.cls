@isTest
private class AccountScoreAndEscalationBatchTest {
    @testSetup
    static void setup() {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 5; i++) {
            accounts.add(new Account(
                Name = 'Batch Test Acc ' + i,
                Priority__c = Math.mod(i, 2) == 0 ? 'High Priority' : 'Standard'
            ));
        }
        insert accounts;

        List<Opportunity> opps = new List<Opportunity>();
        for (Account a : accounts) {
            opps.add(new Opportunity(
                Name = 'Opp for ' + a.Name,
                AccountId = a.Id,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(20),
                Amount = 12000
            ));
        }
        insert opps;
    }

    @isTest
    static void testBatchExecution_happyPath() {
        Set<Id> accountIds = new Map<Id, Account>([SELECT Id FROM Account]).keySet();

        Test.startTest();
        Database.executeBatch(new AccountScoreAndEscalationBatch(accountIds), 200);
        Test.stopTest();

        List<Account> updated = [SELECT Id, Score__c FROM Account WHERE Id IN :accountIds];
        for (Account a : updated) {
            System.assertNotEquals(null, a.Score__c, 'Score should be populated after batch run.');
        }
    }

    @isTest
    static void testBatchExecution_accountGetsFlagged() {
        // Age one of the High Priority opps beyond the 45-day threshold.
        Opportunity toAge = [
            SELECT Id FROM Opportunity
            WHERE AccountId IN (SELECT Id FROM Account WHERE Priority__c = 'High Priority')
            LIMIT 1
        ];
        Test.setCreatedDate(toAge.Id, DateTime.now().addDays(-60));

        Set<Id> accountIds = new Map<Id, Account>([SELECT Id FROM Account WHERE Priority__c = 'High Priority']).keySet();

        Test.startTest();
        Database.executeBatch(new AccountScoreAndEscalationBatch(accountIds), 200);
        Test.stopTest();

        List<Account> flaggedAccounts = [
            SELECT Id, Escalation_Flag__c
            FROM Account
            WHERE Id IN :accountIds AND Escalation_Flag__c = true
        ];
        System.assert(!flaggedAccounts.isEmpty(), 'Expected at least one flagged Account for aged High Priority opp.');
    }

    @isTest
    static void testConstructor_throwsOnEmptySet() {
        Boolean threw = false;
        try {
            new AccountScoreAndEscalationBatch(new Set<Id>());
        } catch (IllegalArgumentException ex) {
            threw = true;
        }
        System.assertEquals(true, threw, 'Constructor should reject an empty Account Id set.');
    }

    @isTest
    static void testBatchExecution_keepsExistingEscalationFlagWhenStillEligible() {
        Account highPriority = [
            SELECT Id
            FROM Account
            WHERE Priority__c = 'High Priority'
            LIMIT 1
        ];
        Opportunity toAge = [
            SELECT Id
            FROM Opportunity
            WHERE AccountId = :highPriority.Id
            LIMIT 1
        ];
        Test.setCreatedDate(toAge.Id, DateTime.now().addDays(-60));

        update new Account(
            Id = highPriority.Id,
            Escalation_Flag__c = true
        );

        Test.startTest();
        Database.executeBatch(new AccountScoreAndEscalationBatch(new Set<Id>{ highPriority.Id }), 200);
        Test.stopTest();

        Account refreshedAccount = [
            SELECT Escalation_Flag__c
            FROM Account
            WHERE Id = :highPriority.Id
        ];
        System.assertEquals(
            true,
            refreshedAccount.Escalation_Flag__c,
            'A rerun should keep the Account flagged.'
        );
    }

    @isTest
    static void testFinish_handlesErrorPreviewState() {
        Account anyAccount = [SELECT Id FROM Account LIMIT 1];
        AccountScoreAndEscalationBatch batch = new AccountScoreAndEscalationBatch(new Set<Id>{ anyAccount.Id });
        batch.totalErrors = 1;
        batch.errorMessages.add('Sample batch error');

        batch.finish(null);

        System.assertEquals(1, batch.totalErrors);
        System.assertEquals(1, batch.errorMessages.size());
    }
}

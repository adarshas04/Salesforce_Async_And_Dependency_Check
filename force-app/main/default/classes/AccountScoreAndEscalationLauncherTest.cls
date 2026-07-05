@isTest
private class AccountScoreAndEscalationLauncherTest {

    @testSetup
    static void setup() {
        insert new Account(Name = 'Launcher Test', Priority__c = 'High Priority');
    }

    @isTest
    static void testLaunch_programmatic() {
        Set<Id> ids = new Map<Id, Account>([SELECT Id FROM Account]).keySet();

        Test.startTest();
        Id jobId = AccountScoreAndEscalationLauncher.launch(ids);
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Batch job Id should be returned.');
    }

    @isTest
    static void testLaunch_throwsOnEmptyIds() {
        Boolean threw = false;
        try {
            AccountScoreAndEscalationLauncher.launch(new Set<Id>());
        } catch (IllegalArgumentException ex) {
            threw = true;
        }
        System.assertEquals(true, threw);
    }

    @isTest
    static void testLaunch_throwsOnInvalidScopeSize() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Boolean threw = false;

        try {
            AccountScoreAndEscalationLauncher.launch(new Set<Id>{ acc.Id }, 0);
        } catch (IllegalArgumentException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Batch scope size must be between 1 and'));
        }

        System.assertEquals(true, threw, 'Launch should reject invalid scope sizes.');
    }

    @isTest
    static void testLaunch_throwsOnNonAccountIds() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = new Contact(LastName = 'Launcher Contact', AccountId = acc.Id);
        insert con;

        Boolean threw = false;
        try {
            AccountScoreAndEscalationLauncher.launch(new Set<Id>{ con.Id });
        } catch (IllegalArgumentException ex) {
            threw = true;
            System.assert(ex.getMessage().contains('Only Account Ids'));
        }

        System.assertEquals(true, threw, 'Launch should reject non-Account Ids.');
    }

    @isTest
    static void testLaunchFromFlow_success() {
        Account acc = [SELECT Id FROM Account LIMIT 1];

        AccountScoreAndEscalationLauncher.LaunchRequest req = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req.accountIds = new List<String>{ acc.Id };

        Test.startTest();
        List<AccountScoreAndEscalationLauncher.LaunchResult> results =
            AccountScoreAndEscalationLauncher.launchFromFlow(new List<AccountScoreAndEscalationLauncher.LaunchRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success);
        System.assertNotEquals(null, results[0].jobId);
    }

    @isTest
    static void testLaunchFromFlow_invalidIdCapturesError() {
        AccountScoreAndEscalationLauncher.LaunchRequest req = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req.accountIds = new List<String>{ 'not-a-valid-id' };

        Test.startTest();
        List<AccountScoreAndEscalationLauncher.LaunchResult> results =
            AccountScoreAndEscalationLauncher.launchFromFlow(new List<AccountScoreAndEscalationLauncher.LaunchRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assertNotEquals(null, results[0].errorMessage);
    }

    @isTest
    static void testLaunchFromFlow_nonAccountIdCapturesError() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        Contact con = new Contact(LastName = 'Flow Contact', AccountId = acc.Id);
        insert con;

        AccountScoreAndEscalationLauncher.LaunchRequest req = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req.accountIds = new List<String>{ con.Id };

        Test.startTest();
        List<AccountScoreAndEscalationLauncher.LaunchResult> results =
            AccountScoreAndEscalationLauncher.launchFromFlow(new List<AccountScoreAndEscalationLauncher.LaunchRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Only Account Ids'));
    }

    @isTest
    static void testLaunchFromFlow_emptyRequestCapturesError() {
        AccountScoreAndEscalationLauncher.LaunchRequest req = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req.accountIds = new List<String>();

        Test.startTest();
        List<AccountScoreAndEscalationLauncher.LaunchResult> results =
            AccountScoreAndEscalationLauncher.launchFromFlow(new List<AccountScoreAndEscalationLauncher.LaunchRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('at least one Account Id'));
    }

    @isTest
    static void testLaunchFromFlow_multipleRequestsShareSingleBatchJob() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
        insert new Account(Name = 'Launcher Test 2', Priority__c = 'Standard');
        Account secondAccount = [SELECT Id FROM Account WHERE Name = 'Launcher Test 2' LIMIT 1];

        AccountScoreAndEscalationLauncher.LaunchRequest req1 = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req1.accountIds = new List<String>{ accounts[0].Id };

        AccountScoreAndEscalationLauncher.LaunchRequest req2 = new AccountScoreAndEscalationLauncher.LaunchRequest();
        req2.accountIds = new List<String>{ secondAccount.Id };

        Test.startTest();
        List<AccountScoreAndEscalationLauncher.LaunchResult> results =
            AccountScoreAndEscalationLauncher.launchFromFlow(
                new List<AccountScoreAndEscalationLauncher.LaunchRequest>{ req1, req2 }
            );
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(true, results[0].success);
        System.assertEquals(true, results[1].success);
        System.assertEquals(results[0].jobId, results[1].jobId);
    }
}

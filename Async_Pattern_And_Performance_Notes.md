# Async Pattern And Performance Notes

## Why This Async Pattern Was Chosen

I chose **Batch Apex** as the primary asynchronous pattern because the requirement is explicitly high-volume, with the solution expected to handle **50,000+ Account evaluations per day**. Batch Apex is the most appropriate Salesforce-native option for this type of workload because it processes records in controlled chunks, resets governor limits for each `execute()` invocation, and provides built-in operational monitoring through `AsyncApexJob`.

The design uses a lightweight launcher class to accept impacted `Account` IDs and delegate the heavy processing to a batch job. This keeps the entry point simple and flexible while ensuring that the actual recalculation and escalation evaluation run in a framework built for scale.

I did not choose **Queueable Apex** as the main processing pattern because queueables are better suited for smaller bounded workloads or orchestration use cases. In this assignment, the core problem is bulk processing at scale, which is where Batch Apex is a better fit.

The implementation also separates business logic from orchestration:

- The **launcher** is responsible only for validation and starting async execution.
- The **batch** is responsible for bulk processing and transaction management.
- The **service class** contains the scoring and escalation rules.

This separation improves readability, testability, and future extensibility.

## Expected Throughput And Performance Considerations

The implementation is designed to support large daily volume by using chunked execution. With the current default batch scope of `200`, Salesforce will divide the total Account set into multiple `execute()` calls, which helps keep **heap usage, CPU usage, SOQL usage, and DML usage** under control per transaction.

For example:

- `3,000` Accounts with scope `200` will run in roughly `15` execute chunks.
- `3,000` Accounts with scope `2,000` will run in `2` execute chunks.

The platform maximum batch scope is `2,000`, but the default of `200` is intentionally conservative and safer for general org load.

Performance was improved by avoiding full Opportunity record hydration. Instead of loading all related open Opportunities into memory, the batch uses an **aggregate query** to retrieve only the summarized values required by the business rules:

- count of open Opportunities
- total open Opportunity amount
- oldest open Opportunity created date

This reduces query payload and heap usage significantly, which is important when processing thousands of Accounts.

The DML strategy is also fully bulkified:

- Accounts are updated in lists rather than record-by-record.
- The scoring and escalation checks are applied in memory per Account after the related Opportunity summary is prepared.

From a throughput perspective, this design should comfortably support the assignment’s stated scale, provided the process is invoked in consolidated batches rather than spawning many overlapping async jobs from high-frequency triggers.

## Additional Production Considerations

For a production-hardened version, I would consider the following enhancements:

- deduping repeated Account requests before launching async work
- preventing redundant concurrent batch launches
- routing small trigger-driven workloads differently from large ones
- adding a scheduled daily sweep if the `> 45 days` escalation rule must be enforced even when no new triggering event occurs

These were intentionally kept out of the core assignment implementation to keep the solution aligned with the stated ask while still leaving a clear path for future scaling improvements.

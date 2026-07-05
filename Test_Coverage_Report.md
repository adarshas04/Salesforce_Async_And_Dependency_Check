# Test Coverage Report

## Scope

This document summarizes the Apex test run executed for both assignment parts.

Included areas:

- Part 1: Account scoring and escalation batch flow
- Part 2: Metadata dependency analyzer services, providers, controller, and API clients

## Test Execution Details

- Org alias: `cpqOrg`
- Test run id: `707dM00001Ua5PY`
- Execution date: `2026-07-06`

## Test Run Summary

- Outcome: `Passed`
- Tests run: `65`
- Passing: `65`
- Failing: `0`
- Total execution time: `9140 ms`

## Part 1 Test Coverage

### Classes covered

| Class | Covered | Uncovered | Coverage |
|---|---:|---:|---:|
| `AccountScoreAndEscalationBatch` | 39 | 9 | 81.25% |
| `AccountScoreAndEscalationLauncher` | 64 | 4 | 94.12% |
| `AccountScoreAndEscalationService` | 35 | 0 | 100.00% |

## Part 2 Test Coverage

### Classes covered

| Class | Covered | Uncovered | Coverage |
|---|---:|---:|---:|
| `ObjectMetadataController` | 45 | 5 | 90.00% |
| `FieldUsageAnalyzerService` | 67 | 8 | 89.33% |
| `ToolingDependencyUsageProvider` | 152 | 27 | 84.92% |
| `ToolingApiRestClient` | 52 | 5 | 91.23% |
| `ReportUsageProvider` | 90 | 24 | 78.95% |
| `ReportTypeMetadataClient` | 120 | 16 | 88.24% |
| `WorkflowUsageProvider` | 129 | 19 | 87.16% |


## Test Classes Executed

### Part 1

- `AccountScoreAndEscalationBatchTest`
- `AccountScoreAndEscalationLauncherTest`
- `AccountScoreAndEscalationServiceTest`

### Part 2

- `ObjectMetadataControllerTest`
- `FieldUsageAnalyzerServiceTest`
- `ToolingDependencyUsageProviderTest`
- `ToolingApiRestClientTest`
- `ReportTypeMetadataClientTest`
- `OptionalProvidersTest`

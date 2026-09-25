import ballerina/workflow.management;

type QualifyingSpend record {|
    decimal medical?;
    decimal commuting?;
    decimal home_energy?;
    decimal professional_travel?;
|};

type ReliefRule record {|
    string label;
    decimal rate;
    decimal cap;
    boolean evidenceRequired;
|};

type Relief record {|
    string category;
    string label;
    decimal qualifyingSpend;
    decimal rate;
    decimal cap;
    decimal deduction;
    boolean capped;
    boolean evidenceRequired;
|};

type Assessment record {|
    int taxYear;
    string filingDeadline;
    decimal grossIncome;
    Relief[] reliefs;
    decimal totalDeductions;
    decimal taxableIncome;
    decimal taxBeforeReliefs;
    decimal taxAfterReliefs;
    decimal estimatedSaving;
    decimal marginalRate;
    string[] evidenceNeeded;
|};

type FiledReturn record {|
    string reference;
    string taxId;
    decimal taxAfterReliefs;
|};

type ReceiptsConfirmation record {|
    boolean attached;
    string note?;
|};

type TaxReturnOutcome record {|
    string status;
    string headline;
    string message;
    string? reference;
|};

type PrepareReturnRequest record {|
    decimal gross_income;
    map<decimal> qualifying_spend;
    string tax_id;
    string user_sub?;
    string transaction_id?;
|};

type ReturnRef record {|
    string instanceId;
    Assessment assessment;
|};

type ReturnStatus record {|
    string status;
    TaxReturnOutcome? outcome = ();
|};

type PendingTasks record {|
    management:HumanTaskGroup[] humanTasks;
    management:ReviewActivitySummary[] approvals;
|};

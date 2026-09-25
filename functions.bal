import ballerina/ai;
import ballerina/log;
import ballerina/uuid;
import ballerina/workflow;

const int TAX_YEAR = 2026;
const string FILING_DEADLINE = "2027-04-30";

final readonly & [decimal?, decimal][] brackets = [[12000, 0.00], [30000, 0.20], [60000, 0.35], [(), 0.45]];

final readonly & map<ReliefRule> reliefRules = {
    medical: {label: "Medical and health expenses", rate: 0.50, cap: 1500, evidenceRequired: false},
    commuting: {label: "Commuting relief", rate: 0.30, cap: 900, evidenceRequired: false},
    home_energy: {label: "Home office and energy relief", rate: 0.20, cap: 600, evidenceRequired: false},
    professional_travel: {label: "Professional travel", rate: 0.25, cap: 1200, evidenceRequired: true}
};

# Prepares a draft income tax assessment for the 2026 tax year under the published rules.
# Every figure comes from the published bracket table and relief rules, never from the model.
# + grossIncome - The citizen's gross income for the year
# + qualifyingSpend - The citizen's total spend per published relief category
# + return - The full assessment: reliefs, deductions, taxable income, tax before and after reliefs, saving and the receipts still needed
@ai:AgentTool
isolated function assessReturn(decimal grossIncome, QualifyingSpend qualifyingSpend) returns Assessment {
    return assess(grossIncome, qualifyingSpend);
}

# Files the tax return with the Ministry of Finance. The citizen must confirm the filing before it runs.
#
# + taxId - The citizen's tax ID
# + grossIncome - The citizen's gross income for the year
# + qualifyingSpend - The citizen's total spend per published relief category
# + return - The filed return with its reference
@workflow:Activity
isolated function fileReturn(string taxId, decimal grossIncome, QualifyingSpend qualifyingSpend) returns FiledReturn|error {
    Assessment assessment = assess(grossIncome, qualifyingSpend);
    FiledReturn filed = {
        reference: string `ASG-${TAX_YEAR}-${uuid:createType4AsString().substring(0, 8).toUpperAscii()}`,
        taxId,
        taxAfterReliefs: assessment.taxAfterReliefs
    };
    log:printInfo("Tax return filed", reference = filed.reference, taxId = taxId,
            taxAfterReliefs = filed.taxAfterReliefs);
    return filed;
}

isolated function assess(decimal grossIncome, QualifyingSpend qualifyingSpend) returns Assessment {
    Relief[] reliefs = computeReliefs(qualifyingSpend);
    decimal totalDeductions = 0;
    string[] evidenceNeeded = [];
    foreach Relief relief in reliefs {
        totalDeductions += relief.deduction;
        if relief.evidenceRequired {
            evidenceNeeded.push(relief.label);
        }
    }
    decimal taxableIncome = decimal:max(grossIncome - totalDeductions, 0).round(2);
    decimal before = taxDue(grossIncome);
    decimal after = taxDue(taxableIncome);
    return {
        taxYear: TAX_YEAR,
        filingDeadline: FILING_DEADLINE,
        grossIncome: grossIncome.round(2),
        reliefs,
        totalDeductions: totalDeductions.round(2),
        taxableIncome,
        taxBeforeReliefs: before,
        taxAfterReliefs: after,
        estimatedSaving: (before - after).round(2),
        marginalRate: marginalRate(taxableIncome),
        evidenceNeeded
    };
}

isolated function computeReliefs(QualifyingSpend qualifyingSpend) returns Relief[] {
    Relief[] reliefs = [];
    foreach [string, ReliefRule] [category, rule] in reliefRules.entries() {
        decimal spend = (qualifyingSpend[category] ?: 0d).round(2);
        if spend <= 0d {
            continue;
        }
        decimal raw = spend * rule.rate;
        reliefs.push({
            category,
            label: rule.label,
            qualifyingSpend: spend,
            rate: rule.rate,
            cap: rule.cap,
            deduction: decimal:min(raw, rule.cap).round(2),
            capped: raw > rule.cap,
            evidenceRequired: rule.evidenceRequired
        });
    }
    return reliefs;
}

isolated function taxDue(decimal taxableIncome) returns decimal {
    decimal remaining = decimal:max(taxableIncome, 0);
    decimal lower = 0;
    decimal total = 0;
    foreach [decimal?, decimal] [upper, rate] in brackets {
        decimal band = upper is decimal ? upper - lower : remaining;
        decimal taxed = decimal:min(remaining, band);
        if taxed <= 0d {
            break;
        }
        total += taxed * rate;
        remaining -= taxed;
        if upper is decimal {
            lower = upper;
        }
    }
    return total.round(2);
}

isolated function marginalRate(decimal taxableIncome) returns decimal {
    foreach [decimal?, decimal] [upper, rate] in brackets {
        if upper is () || taxableIncome < upper {
            return rate;
        }
    }
    return brackets[brackets.length() - 1][1];
}

isolated function toQualifyingSpend(map<decimal> spend) returns QualifyingSpend|error {
    map<decimal> published = {};
    foreach [string, decimal] [category, amount] in spend.entries() {
        if reliefRules.hasKey(category) {
            published[category] = amount;
        }
    }
    return published.cloneWithType();
}

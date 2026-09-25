import ballerina/http;
import ballerina/workflow;
import ballerina/workflow.management;
import ballerinax/amp as _;

service /tax\-agent on new http:Listener(8014) {

    resource function get health() returns json {
        return {status: "healthy"};
    }

    resource function post prepare\-return(@http:Payload PrepareReturnRequest request) returns ReturnRef|error {
        QualifyingSpend qualifyingSpend = check toQualifyingSpend(request.qualifying_spend);
        string instanceId = check taxAgent.run(string `Prepare and file the 2026 tax return.
Tax ID: ${request.tax_id}
Gross income: ${request.gross_income}
Qualifying spend: ${qualifyingSpend.toJsonString()}`);
        return {instanceId, assessment: assess(request.gross_income, qualifyingSpend)};
    }

    resource function get tax\-returns/[string instanceId]() returns ReturnStatus|error {
        string|error summary = taxAgent.getResult(instanceId);
        if summary is workflow:AgentBusyError {
            return {status: "in progress"};
        }
        return {status: "completed", summary: check summary};
    }

    resource function get tax\-returns/[string instanceId]/tasks() returns PendingTasks|error {
        management:HumanTaskGroup[] humanTasks = check management:listPendingHumanTasks(instanceId);
        management:ReviewActivitySummary[] approvals = check management:listPendingReviewActivities(instanceId);
        return {humanTasks, approvals};
    }

    resource function post tasks/[string taskId](@http:Header {name: "x-user-role"} string role,
            @http:Payload ReceiptsConfirmation confirmation) returns error? {
        check management:completeHumanTask(taskId, confirmation, callerRoles = [role]);
    }

    resource function post approvals/[string taskId](@http:Header {name: "x-user-role"} string role,
            @http:Payload management:ReviewDecision decision) returns error? {
        check management:completeReviewActivity(taskId, decision, callerRoles = [role]);
    }
}

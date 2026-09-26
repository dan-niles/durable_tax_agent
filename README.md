# Durable Tax Filing Agent

A durable AI agent for the Kingdom of Asgard's Ministry of Finance, written in Ballerina with `ballerina/workflow`'s `DurableAgent`. It prepares a citizen's 2026 income tax return, waits for the citizen to confirm receipts where a relief needs them, waits for the citizen to confirm the filing, and then files the return exactly once.

It is a durable rewrite of the Python `tax-agent` in [fcto-demos/bank-of-asgard](https://github.com/fcto-demos/bank-of-asgard). The tax rules are the same: progressive brackets (0% to 12,000; 20% to 30,000; 35% to 60,000; 45% above) and four relief categories with fixed rates and annual caps.

| Category | Rate | Annual cap | Receipts needed |
| --- | --- | --- | --- |
| `medical` | 50% | 1,500 | no |
| `commuting` | 30% | 900 | no |
| `home_energy` | 20% | 600 | no |
| `professional_travel` | 25% | 1,200 | yes |

Unknown categories are ignored. The model never computes a figure: every number comes from the `assessReturn` tool, and the model only explains the result.

## Why durable

A run can wait hours or days for the citizen without holding a request or a process open. Its state lives in a Temporal server, so it survives restarts, redeploys and crashes:

- Steps that already finished are never run again after a restart. `fileReturn` runs once, even if the agent is redeployed while it waits.
- The run pauses on two human steps: the `receipts` task (only when a relief needs evidence) and the approval that gates `fileReturn`.

## How it works

1. `POST /prepare-return` starts a run and returns its `instanceId` and the draft assessment.
2. The agent calls `assessReturn`.
3. If a relief needs receipts, the run waits on the `receipts` task until the citizen confirms.
4. The agent proposes `fileReturn`. The run waits until the citizen approves it.
5. `fileReturn` files the return and returns a reference such as `ASG-2026-95A8FEA5`.
6. The agent writes a short summary. `GET /tax-returns/{instanceId}` returns it.

## API

The service listens on port `8014` under `/tax-agent`.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Health check |
| `POST` | `/prepare-return` | Start a return; returns the `instanceId` and the draft assessment |
| `GET` | `/tax-returns/{instanceId}` | Status (`in progress` or `completed`) and the final summary |
| `GET` | `/tax-returns/{instanceId}/tasks` | The `receipts` task and the filing approval waiting for the citizen |
| `POST` | `/tasks/{taskId}` | Confirm the receipts |
| `POST` | `/approvals/{taskId}` | Confirm or reject the filing |

The two `POST` endpoints for tasks need the header `x-user-role: citizen`.

## Sample requests

The examples use a local run (`http://localhost:8014`). On Agent Manager, use the agent's URL from the console (for example `http://default-default.am-gateway.localhost:19080/durable-tax-agent`) without `/tax-agent`, and add `-H 'X-API-Key: <key>'`.

**1. Start a return**

```bash
curl -X POST http://localhost:8014/tax-agent/prepare-return \
  -H 'Content-Type: application/json' \
  -d '{
    "gross_income": 52000,
    "qualifying_spend": {"medical": 900, "commuting": 1400, "professional_travel": 2000},
    "tax_id": "ASG-TAX-1001"
  }'
```

The response holds the `instanceId` and the draft assessment: total deductions 1370, taxable income 50630, tax before reliefs 11300, tax after reliefs 10820.5, a saving of 479.5, and `"evidenceNeeded": ["Professional travel"]`.

**2. Find the receipts task**

```bash
curl http://localhost:8014/tax-agent/tax-returns/<instanceId>/tasks
```

```json
{"humanTasks": [{"taskName": "taxAgent.receipts", "taskIds": ["<receiptsTaskId>"]}], "approvals": []}
```

**3. Confirm the receipts**

```bash
curl -X POST http://localhost:8014/tax-agent/tasks/<receiptsTaskId> \
  -H 'Content-Type: application/json' -H 'x-user-role: citizen' \
  -d '{"attached": true, "note": "Uploaded 3 travel receipts"}'
```

Send `{"attached": false}` to stop without filing.

**4. Find the filing approval**

```bash
curl http://localhost:8014/tax-agent/tax-returns/<instanceId>/tasks
```

`approvals[0].taskId` is the approval for `fileReturn`, titled "Confirm and file your tax return".

**5. Confirm the filing**

```bash
curl -X POST http://localhost:8014/tax-agent/approvals/<approvalTaskId> \
  -H 'Content-Type: application/json' -H 'x-user-role: citizen' \
  -d '{"action": "proceed"}'
```

`action` is `proceed`, `proceed-with-input` (with an edited `input`) or `reject` (with optional `feedback`).

**6. Read the outcome**

```bash
curl http://localhost:8014/tax-agent/tax-returns/<instanceId>
```

```json
{"status": "completed", "summary": "Your 2026 tax return has been prepared and filed successfully. ... Your filing reference is ASG-2026-95A8FEA5 ..."}
```

## Run Temporal

The agent needs a Temporal server. For local development and demos, run the Temporal dev server in Docker:

```bash
docker run -d --name temporal \
  -p 7233:7233 -p 8233:8233 \
  -v temporal-data:/data \
  temporalio/temporal:latest \
  server start-dev --ip 0.0.0.0 --db-filename /data/temporal.db
```

- `7233` is the gRPC endpoint the agent connects to; `8233` is the Temporal UI (http://localhost:8233).
- `--db-filename` keeps runs in a volume, so they survive a restart of the container.

Or, with the [Temporal CLI](https://docs.temporal.io/cli) installed: `temporal server start-dev --db-filename ./temporal.db`.

For production, use Temporal Cloud or a self-hosted Temporal cluster with a persistent database.

## Run locally

1. Start Temporal (above).
2. Create `Config.toml` (it is gitignored):

   ```toml
   openRouterApiKey = "<your OpenRouter key>"

   [ballerina.workflow]
   mode = "LOCAL"
   taskQueue = "durable-tax-agent"
   ```

3. Run the agent:

   ```bash
   bal run
   ```

The model is GPT-4o mini through [OpenRouter](https://openrouter.ai) (`connections.bal`).

## Deploy on WSO2 Agent Manager

### 1. Create the agent

In the console, create a **platform-hosted** agent with these settings:

| Field | Value |
| --- | --- |
| Repository | `https://github.com/dan-niles/durable_tax_agent`, branch `main`, path `/` |
| Build type | Ballerina |
| Interface type | Custom API |
| Port | `8014` |
| Base path | `/tax-agent` |
| OpenAPI spec | `/openapi.yaml` |

Or with `amctl` and a manifest:

```yaml
apiVersion: agent-manager.wso2.com/v1alpha1
kind: Agent
spec:
  name: durable-tax-agent
  displayName: Durable Tax Filing Agent
  agentType: {type: agent-api, subType: custom-api}
  provisioning:
    type: internal
    repository: {url: https://github.com/dan-niles/durable_tax_agent, branch: main, appPath: /}
  build: {type: buildpack, buildpack: {language: ballerina}}
  inputInterface: {type: HTTP, port: 8014, basePath: /tax-agent, schema: {path: /openapi.yaml}}
  configurations:
    enableAutoInstrumentation: true
    env:
      - {key: BAL_CONFIG_VAR_BALLERINA_WORKFLOW_URL, value: "<temporal-host>:7233"}
      - {key: BAL_CONFIG_VAR_BALLERINA_WORKFLOW_TASKQUEUE, value: durable-tax-agent-amp}
      - {key: BAL_CONFIG_VAR_OPENROUTERAPIKEY, value: "<your OpenRouter key>", isSensitive: true}
```

```bash
amctl agent create -f agent.yaml --project default
```

### 2. Environment variables

Ballerina reads configuration on Agent Manager only from `BAL_CONFIG_VAR_<NAME>` environment variables. A `BAL_CONFIG_VAR_*` variable that nothing reads stops the program at startup, so set only these:

| Variable | Value |
| --- | --- |
| `BAL_CONFIG_VAR_OPENROUTERAPIKEY` | Your OpenRouter key (mark as secret) |
| `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_URL` | Temporal's gRPC address, `<host>:<port>` |
| `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_TASKQUEUE` | A task queue used only by this deployment, for example `durable-tax-agent-amp` |

`LOCAL` mode is the default and connects without TLS, which suits a Temporal dev server. For a server with TLS, also set:

| Variable | Value |
| --- | --- |
| `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_MODE` | `SELF_HOSTED` (or `CLOUD` for Temporal Cloud) |
| `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_NAMESPACE` | The Temporal namespace |
| `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_AUTHAPIKEY` | An API key, as a secret |

TLS is used only when an API key, an mTLS certificate or a CA certificate is set. mTLS certificate files can be added as file mounts. Each mount's `mountPath` is a folder, the file appears at `<mountPath>/<key>`, and each folder holds one file.

Use a separate task queue for each deployment. Two deployments that share a task queue on the same Temporal namespace take each other's work.

### 3. Let Agent Manager reach Temporal

Agent pods can only make outbound calls to public hosts on ports 80 and 443 and to the platform gateway. Port `7233` is blocked. Choose one:

**A. Temporal behind TLS on port 443 at a public address.** Put Temporal behind a TLS proxy (for example Caddy with `reverse_proxy h2c://127.0.0.1:7233`, or nginx with `grpc_pass`) on a host with a public IP, and set `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_URL` to `<hostname>:443` in `SELF_HOSTED` mode. Protect it with mTLS or an API key: an open Temporal server exposes every run's history and lets anyone start or stop runs.

**B. Allow egress to Temporal (local k3d install).** When Temporal runs on the same machine as a local Agent Manager, add a NetworkPolicy that lets the agent's pod reach it on `7233`.

1. Find the address the cluster uses to reach the Docker host:

   ```bash
   docker network inspect k3d-amp-local --format '{{(index .IPAM.Config 0).Gateway}}'
   ```

   This is the address for Temporal running as a Docker container with `-p 7233:7233`. For Temporal running directly on a macOS host under Rancher Desktop, use `192.168.5.2`.

2. Find the agent's data-plane namespace:

   ```bash
   docker exec k3d-amp-local-server-0 kubectl get ns | grep '^dp-'
   ```

3. Apply the policy, replacing `<namespace>` and `<temporal-ip>`:

   ```yaml
   apiVersion: networking.k8s.io/v1
   kind: NetworkPolicy
   metadata:
     name: allow-temporal-egress
     namespace: <namespace>
   spec:
     podSelector:
       matchLabels:
         openchoreo.dev/component: durable-tax-agent
     policyTypes: [Egress]
     egress:
       - to:
           - ipBlock:
               cidr: <temporal-ip>/32
         ports:
           - port: 7233
             protocol: TCP
   ```

   ```bash
   docker cp allow-temporal-egress.yaml k3d-amp-local-server-0:/tmp/
   docker exec k3d-amp-local-server-0 kubectl apply -f /tmp/allow-temporal-egress.yaml
   ```

   Select the pod by `openchoreo.dev/component`. Agent pods do not carry the `amp.wso2.com/workload=agent` label.

4. Set `BAL_CONFIG_VAR_BALLERINA_WORKFLOW_URL` to `<temporal-ip>:7233`.

When the pod starts, its log shows `Registered the WorkflowKind search attribute`, and Temporal lists the pod as a poller on the task queue:

```bash
temporal task-queue describe --task-queue durable-tax-agent-amp
```

### 4. Allow the `x-user-role` header (CORS)

The console's **Try It** page runs in the browser, and the agent's default CORS settings allow only `authorization`, `Content-Type`, `Origin` and `X-API-Key`. Under **Configure → CORS**, add `x-user-role` to the allowed headers. Without it, the task and approval requests fail with "Failed to fetch", and the console reports it as an unauthorized test key.

### 5. Try the durability

1. Start a return that includes `professional_travel`, and wait until `GET /tax-returns/{instanceId}/tasks` shows the `receipts` task.
2. Click **Suspend** on the agent's Deploy page. In the Temporal UI, the run is still `Running`.
3. Click **Re-deploy**. The new pod picks the run up again.
4. Confirm the receipts, then the filing. The run completes, and `fileReturn` appears once in its history.

## Project layout

| File | Contents |
| --- | --- |
| `workflows.bal` | The `taxAgent` durable agent: prompt, tools, gated activity, human task |
| `functions.bal` | The tax rules, the `assessReturn` tool and the `fileReturn` activity |
| `main.bal` | The HTTP service |
| `types.bal` | Request, assessment and response types |
| `connections.bal` | The model provider |
| `config.bal` | Configurable values |
| `openapi.yaml` | The API spec Agent Manager uses for Try It |

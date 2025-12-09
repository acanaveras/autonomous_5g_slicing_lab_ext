# Quick Start Guide - NAT Features

## 5 Minute Setup

### 1. Install Dependencies

```bash
cd agentic-llm/nat_wrapper
uv pip install -e .
```

This installs the new dependencies:
- `psutil` - Performance profiling
- `opentelemetry-api/sdk` - Observability infrastructure
- `arize-phoenix` - Distributed tracing

### 2. Verify Configuration

Check that features are enabled in `config.yml`:

```bash
grep -A 15 "Profiling Configuration" src/nat_5g_slicing/configs/config.yml
```

**Expected output:**
```yaml
# Profiling Configuration
profiling_enabled: true
profiling_output_dir: ./profiles
slow_warning_threshold_ms: 5000

# Guardrails Configuration
guardrails_enabled: true
validation_mode: strict

# Phoenix Observability Configuration
phoenix_enabled: true
phoenix_endpoint: http://0.0.0.0:6006
...
```

### 3. Start NAT Server

```bash
nat serve \
  --config_file src/nat_5g_slicing/configs/config.yml \
  --host 0.0.0.0 \
  --port 4999
```

**Expected logs:**
```
Performance profiler initialized
Guardrails initialized with mode: strict
Phoenix observability enabled: http://0.0.0.0:6006
NAT server started on port 4999
```

### 4. Test the Features

#### Test 1: Valid Request (Should Succeed)
```bash
curl -X POST http://localhost:4999/generate \
  -H "Content-Type: application/json" \
  -d '{"input_message": "Monitor packet loss and reconfigure if needed"}'
```

**Look for in logs:**
```
[EXECUTING] get_packetloss_logs with limit=20
[GUARDRAIL] LLM response validation passed
[PROFILE] get_packetloss_logs | Time: 1234.56ms | Memory: 2.45MB | Status: success
```

#### Test 2: Invalid Request (Should Fail with Guardrail)
```bash
curl -X POST http://localhost:4999/generate \
  -H "Content-Type: application/json" \
  -d '{"input_message": "Reconfigure UE2 to 90/10"}'
```

**Look for in logs:**
```
[GUARDRAIL] Invalid input: Invalid UE: UE3. Must be 'UE1' or 'UE2'
ERROR: Validation failed
```

### 5. View Profiling Report

After the server shuts down (Ctrl+C), check the profiling report:

```bash
# Find the latest report
ls -lt ./profiles/

# View it
cat ./profiles/performance_report_*.json | jq .
```

**Expected structure:**
```json
{
  "get_packetloss_logs": {
    "total_calls": 1,
    "successful_calls": 1,
    "avg_time_ms": 5234.56,
    "max_time_ms": 5234.56,
    "min_time_ms": 5234.56,
    "avg_memory_mb": 2.34,
    "max_memory_mb": 2.34,
    "success_rate": 1.0,
    "slow_executions": 1
  }
}
```

---

## Common Use Cases

### Use Case 1: Disable Guardrails Temporarily

```bash
export GUARDRAILS_ENABLED=false
nat serve --config_file config.yml --port 4999
```

### Use Case 2: Switch to Warning Mode

```bash
export VALIDATION_MODE=warning
nat serve --config_file config.yml --port 4999
```

Now invalid requests will log warnings but continue executing.

### Use Case 3: Adjust Performance Thresholds

```bash
export SLOW_WARNING_THRESHOLD_MS=10000  # 10 seconds
nat serve --config_file config.yml --port 4999
```

### Use Case 4: Disable Profiling

```bash
export PROFILING_ENABLED=false
nat serve --config_file config.yml --port 4999
```

---

## View Real-Time Logs

### Watch All Activity
```bash
tail -f logs/nat_server.log
```

### Watch Only Profiling
```bash
tail -f logs/nat_server.log | grep PROFILE
```

### Watch Only Guardrails
```bash
tail -f logs/nat_server.log | grep GUARDRAIL
```

### Watch Only Execution
```bash
tail -f logs/nat_server.log | grep EXECUTING
```

---

## Phoenix Observability (Optional)

### Setup Phoenix Server

**Option 1: Docker (Recommended)**
```bash
docker run -d \
  -p 6006:6006 \
  -p 4317:4317 \
  --name phoenix \
  arizephoenix/phoenix:latest
```

**Option 2: Python**
```bash
pip install arize-phoenix
phoenix serve
```

### Access Phoenix UI

```
http://0.0.0.0:6006
```

### Enable Phoenix in NAT

```bash
export PHOENIX_ENABLED=true
export PHOENIX_ENDPOINT=http://0.0.0.0:6006

nat serve --config_file config.yml --port 4999
```

---

## Troubleshooting

### Issue: Module not found errors

**Solution:**
```bash
cd agentic-llm/nat_wrapper
uv pip install openinference-instrumentation-langchain arize-phoenix-otel
uv pip install -e .
```

### Issue: Permission denied for ./profiles

**Solution:**
```bash
mkdir -p ./profiles
chmod 755 ./profiles
```

### Issue: Profiling reports not generated

**Solution:**
- Ensure profiling is enabled: `grep profiling_enabled config.yml`
- Check server logs: `tail -f logs/nat_server.log | grep PROFILE`
- Verify directory exists: `ls -la ./profiles/`

### Issue: Too many guardrail errors

**Solution:**
Switch to warning mode:
```bash
export VALIDATION_MODE=warning
```

Or disable temporarily:
```bash
export GUARDRAILS_ENABLED=false
```

### Issue: Phoenix connection failed

**Solution:**
1. Check if Phoenix is running:
   ```bash
   curl http://0.0.0.0:6006/health
   ```

2. If not, start it:
   ```bash
   docker run -p 6006:6006 arizephoenix/phoenix:latest
   ```

3. Or disable Phoenix:
   ```bash
   export PHOENIX_ENABLED=false
   ```

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `PROFILING_ENABLED` | `true` | Enable performance profiling |
| `GUARDRAILS_ENABLED` | `true` | Enable validation |
| `VALIDATION_MODE` | `strict` | `strict`, `warning`, or `disabled` |
| `SLOW_WARNING_THRESHOLD_MS` | `5000` | Threshold for slow warnings (ms) |
| `PROFILING_OUTPUT_DIR` | `./profiles` | Profiling reports directory |
| `PHOENIX_ENABLED` | `true` | Enable Phoenix tracing |
| `PHOENIX_ENDPOINT` | `http://0.0.0.0:6006` | Phoenix server URL |

---

## What to Expect

### Successful Request Flow

```
1. Request received
2. [EXECUTING] get_packetloss_logs with limit=20
3. [GUARDRAIL] LLM response validation passed
4. [PROFILE] get_packetloss_logs | Time: 5234ms | Memory: 2.34MB | Status: success
5. [EXECUTING] reconfigure_network with UE=UE1, value_1_old=50, value_2_old=50
6. [GUARDRAIL] Output validation passed
7. [PROFILE] reconfigure_network | Time: 11234ms | Memory: 12.45MB | Status: success
8. Response sent
```

### Invalid Request Flow

```
1. Request received
2. [EXECUTING] reconfigure_network with UE=UE3, value_1_old=50, value_2_old=50
3. [GUARDRAIL] Invalid input: Invalid UE: UE3. Must be 'UE1' or 'UE2'
4. ERROR: Validation failed
5. Error response sent
```

---
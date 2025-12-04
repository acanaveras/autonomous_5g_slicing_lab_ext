# 🚀 GPU Machine Setup Commands

Run these commands **ON YOUR GPU UBUNTU MACHINE** to complete the NeMo UI integration.

## ⚡ Quick Start (Copy-Paste All Commands)

```bash
# Step 1: Navigate to project directory
cd /home/ubuntu/autonomous_5g_slicing_lab_ext

# Step 2: Pull latest changes (includes scripts we just created)
git pull origin nemo-agentic-toolkit-wrapper

# Step 3: Make scripts executable
chmod +x scripts/*.sh

# Step 4: Run the setup script
./scripts/setup-nemo-ui.sh

# Step 5: Start all services
./scripts/start-all-services.sh
```

That's it! The NeMo UI should now be running on port 5001.

---

## 📋 Step-by-Step Detailed Instructions

### Step 1: Update Your Code

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
git pull origin nemo-agentic-toolkit-wrapper
```

This pulls the scripts and configuration files we just created.

### Step 2: Make Scripts Executable

```bash
chmod +x scripts/*.sh
# Or run the helper script:
bash scripts/make-executable.sh
```

### Step 3: Run Setup

```bash
./scripts/setup-nemo-ui.sh
```

This will:
- Add NeMo UI as a git submodule
- Install Node.js dependencies
- Create `.env` configuration
- Verify NAT server is running

**Expected output:**
```
🚀 Setting up NeMo Agent Toolkit UI
====================================

📦 Step 1/5: Adding NeMo UI as git submodule...
✅ Submodule added successfully

📦 Step 2/5: Installing Node.js dependencies...
✅ Dependencies installed

⚙️  Step 3/5: Creating .env configuration...
✅ .env file created

🔍 Step 4/5: Checking NAT server availability...
✅ NAT server is accessible on port 4999

📝 Step 5/5: Committing changes to git...

====================================
✅ Setup complete!
```

### Step 4: Start Services

**Option A: Start Everything at Once**
```bash
./scripts/start-all-services.sh
```

**Option B: Start Services Individually**
```bash
# Start Phoenix
docker run -d -p 6006:6006 -p 4317:4317 --name phoenix arizephoenix/phoenix:latest

# Start NAT Server
cd agentic-llm/nat_wrapper
nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999 &

# Start NeMo UI
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
./scripts/start-nemo-ui.sh
```

### Step 5: Verify Everything is Running

```bash
./scripts/check-services.sh
```

**Expected output:**
```
🔍 Checking 5G Network Agent Services Status
==============================================

✅ NAT Server is RUNNING (Port: 4999, PID: 12345)
   URL: http://localhost:4999

✅ NeMo UI is RUNNING (Port: 5001, PID: 12346)
   URL: http://localhost:5001

✅ Phoenix is RUNNING (Port: 6006, PID: 12347)
   URL: http://localhost:6006
```

### Step 6: Access the UI

If your GPU machine is **local**:
- Open browser to: http://localhost:5001

If your GPU machine is **remote**, set up SSH port forwarding:

```bash
# On your local Windows/Mac machine:
ssh -L 5001:localhost:5001 ubuntu@<your-gpu-ip>
```

Then open: http://localhost:5001

---

## 🧪 Testing the Integration

### Test 1: NAT Server Endpoint

```bash
curl -X POST http://localhost:4999/generate \
  -H "Content-Type: application/json" \
  -d '{"input_message": "What can you do?"}'
```

**Expected:** JSON response with network monitoring capabilities

### Test 2: NeMo UI Access

```bash
curl http://localhost:5001
```

**Expected:** HTML content (Next.js app)

### Test 3: Chat with Agent

1. Open http://localhost:5001 in browser
2. Type: "Monitor packet loss for all UEs"
3. You should see the agent respond

### Test 4: Check All Ports

```bash
lsof -i :4999,5001,6006
```

**Expected:**
```
COMMAND    PID    USER   FD   TYPE   DEVICE SIZE/OFF NODE NAME
node     12345  ubuntu   21u  IPv4  1234567      0t0  TCP *:5001 (LISTEN)
python   12346  ubuntu   22u  IPv4  1234568      0t0  TCP *:4999 (LISTEN)
docker   12347  ubuntu   23u  IPv4  1234569      0t0  TCP *:6006 (LISTEN)
```

---

## 🛠️ Common Operations

### View Logs

```bash
# NAT Server
tail -f /tmp/nat-server.log

# NeMo UI
tail -f /tmp/nemo-ui.log

# Both at once
tail -f /tmp/nat-server.log /tmp/nemo-ui.log
```

### Restart NeMo UI

```bash
# Stop
kill $(lsof -ti:5001)

# Start
./scripts/start-nemo-ui.sh
```

### Stop All Services

```bash
./scripts/stop-all-services.sh
```

### Update NeMo UI

```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/nemo-ui
git pull origin main
npm ci
npm run build  # If using production mode
```

---

## 🔧 Troubleshooting

### Problem: "npm: command not found"

**Solution:** Install Node.js
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version  # Should be >= 18.0.0
```

### Problem: "nat: command not found"

**Solution:** Install NAT
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext/agentic-llm/nat_wrapper
uv pip install -e .
```

### Problem: Port 5001 already in use

**Solution:** Kill the process
```bash
kill $(lsof -ti:5001)
```

### Problem: NAT Server not responding

**Solution:** Check if it's running
```bash
# Check process
ps aux | grep nat

# Check logs
tail -f /tmp/nat-server.log

# Restart
cd agentic-llm/nat_wrapper
nat serve --config_file src/nat_5g_slicing/configs/config.yml --host 0.0.0.0 --port 4999
```

### Problem: Submodule not cloning

**Solution:** Manual clone
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
rm -rf nemo-ui
git clone https://github.com/NVIDIA/NeMo-Agent-Toolkit-UI.git nemo-ui
cd nemo-ui
npm ci
```

---

## 📊 Service Port Reference

| Service | Port | Purpose |
|---------|------|---------|
| NAT Server | 4999 | Backend API |
| NeMo UI | 5001 | Chat Interface |
| Phoenix | 6006 | Tracing/Observability |
| Streamlit | 8501 | Monitoring Dashboard |

---

## ✅ Success Checklist

After running all commands, you should have:

- [ ] NeMo UI submodule cloned
- [ ] Node modules installed
- [ ] `.env` file created in `nemo-ui/`
- [ ] All scripts executable
- [ ] NAT server running on port 4999
- [ ] NeMo UI running on port 5001
- [ ] Phoenix running on port 6006
- [ ] Can access http://localhost:5001 in browser
- [ ] Can chat with the agent

---

## 🎯 Next Steps

1. **Commit your changes:**
```bash
cd /home/ubuntu/autonomous_5g_slicing_lab_ext
git add .gitmodules nemo-ui
git commit -m "Add NeMo Agent Toolkit UI integration (port 5001)"
git push origin nemo-agentic-toolkit-wrapper
```

2. **Test the agent:**
   - Open http://localhost:5001
   - Try: "Monitor packet loss and reconfigure if needed"
   - Watch the agent work!

3. **Compare UIs:**
   - NeMo UI: http://localhost:5001 (Chat interface)
   - Streamlit: http://localhost:8501 (Monitoring dashboard)

---

## 📞 Getting Help

If something doesn't work:

1. Run: `./scripts/check-services.sh`
2. Check logs in `/tmp/`
3. Review `NEMO_UI_SETUP.md` for detailed troubleshooting


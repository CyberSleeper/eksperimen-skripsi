# Quick Start Guide

Get started with the cache performance testing framework in 5 minutes!

## Prerequisites Checklist

- [ ] K6 installed
- [ ] Python 3.x installed
- [ ] SSH access to target VMs
- [ ] PostgreSQL on target VMs
- [ ] Application running on target VMs

## 5-Minute Setup

### 1. Clone and Configure (2 minutes)

```bash
# Clone repository
git clone <your-repo-url>
cd skripsi_gilang_eksperimen

# Make scripts executable
chmod +x *.sh

# Create configuration
cp config.env.example config.env
nano config.env  # Edit with your VM IPs and SSH key path
```

**Edit config.env:**
```bash
VM_NO_CACHE="13.214.170.49"        # Your no-cache VM IP
VM_CACHE="18.141.211.240"          # Your cache VM IP
VM_CACHE_BACKUP="52.77.228.157"    # Your backup cache VM IP
SSH_KEY="~/.ssh/id_ed25519"        # Your SSH key
SSH_USER="ubuntu"                  # SSH username
```

### 2. Generate Seed Data (1 minute)

```bash
# Generate seed file for 100 records (small test)
echo 100 | python gen_income.py

# Verify
ls -lh seeds/
# Should show: seed_income_100_records.sql
```

### 3. Run Your First Test (2 minutes)

```bash
# Run 3 test iterations with 100 records payload
./run_multiple_tests.sh 3 100

# Watch the output - it will:
# ✓ Clear caches
# ✓ Warm up cache
# ✓ Run tests on all 3 VMs
# ✓ Save results to results/ folder
```

### 4. Check Results

```bash
# View results
ls -lh results/

# Quick look at latest result
cat results/test_100_records_100_automatic_run1_*.json | jq .

# See performance summary
cat results/test_100_records_100_automatic_run1_*.csv
```

## What Just Happened?

Your test just:

1. ✅ **Cleared nginx cache** on cache VMs
2. ✅ **Warmed up cache** with initial requests
3. ✅ **Started resource monitoring** (CPU, memory)
4. ✅ **Ran K6 load tests** against:
   - No-Cache VM (baseline)
   - Cache VM (measuring HITs)
   - Cache VM with cache-bust (measuring MISSs)
5. ✅ **Collected metrics**:
   - Response times (avg, P90, P95, P99)
   - APDEX scores
   - Cache hit rates
   - Resource usage
6. ✅ **Saved results** as JSON and CSV

## Next Steps

### Run Full Experiment

```bash
# First, generate all seed files
for size in 10 100 500 1000 2000 4000 8000 16000 32000; do
    echo $size | python gen_income.py
done

# Run full experiment (takes ~6-8 hours)
./run_full_experiment.sh

# This will test all payload sizes automatically
```

### Analyze Results

**Option 1: PowerShell (Windows)**
```powershell
.\combine_detailed_results.ps1
# Creates: results/detailed_all_tests_<timestamp>.csv
```

**Option 2: Jupyter Notebook**
```bash
# Install dependencies
pip install jupyter pandas matplotlib seaborn

# Open notebook
jupyter notebook cache_performance_eda.ipynb

# Run all cells to see visualizations
```

**Option 3: Excel/Google Sheets**
```
1. Open results/detailed_all_tests_<timestamp>.csv
2. Create pivot tables
3. Generate charts
```

## Common First-Time Issues

### Issue: "Permission denied" when running scripts

**Fix:**
```bash
chmod +x *.sh
```

### Issue: "K6 command not found"

**Fix:**
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install k6

# Or download binary
wget https://github.com/grafana/k6/releases/download/v0.47.0/k6-v0.47.0-linux-amd64.tar.gz
tar -xzf k6-v0.47.0-linux-amd64.tar.gz
sudo mv k6-v0.47.0-linux-amd64/k6 /usr/local/bin/
```

### Issue: "SSH connection refused"

**Fix:**
```bash
# Test connection
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-ip> "echo OK"

# Copy key if needed
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<vm-ip>

# Check key permissions
chmod 600 ~/.ssh/id_ed25519
```

### Issue: "Seed file not found"

**Fix:**
```bash
# Generate the seed file
echo 100 | python gen_income.py

# Check it was created
ls -lh seeds/
```

## Understanding Your Results

### JSON Output Structure

```json
{
  "test_configuration": {
    "payload_size": "100",
    "test_run_id": "test_100_automatic_run1_...",
    "apdex_t": 500,  // Satisfied threshold (ms)
    "apdex_f": 1500  // Frustrated threshold (ms)
  },
  "no_cache": {
    "total_requests": 150,
    "apdex_score": 0.85,
    "response_times": {
      "avg": 450.5,
      "p95": 650.2,
      "p99": 780.3
    }
  },
  "cache_hit": {
    "apdex_score": 0.98,  // Better!
    "response_times": {
      "avg": 120.3  // Much faster!
    }
  },
  "cache_statistics": {
    "hit_rate": 95.5,  // 95.5% cache hits
    "improvement_hit_vs_nocache": 73.2  // 73.2% faster with cache
  }
}
```

### Key Metrics Explained

**APDEX Score** (0 to 1, higher is better):
- 0.94 - 1.00: Excellent 🟢
- 0.85 - 0.93: Good 🟡
- 0.70 - 0.84: Fair 🟠
- < 0.70: Poor 🔴

**Response Time Percentiles**:
- P50 (median): 50% of requests faster than this
- P90: 90% of requests faster than this
- P95: 95% of requests faster than this (good SLA metric)
- P99: 99% of requests faster than this (tail latency)

**Cache Hit Rate**:
- > 90%: Excellent caching
- 70-90%: Good caching
- < 70%: Review cache configuration

**Improvement %**:
- Shows how much faster cache is vs no cache
- Higher = better cache performance

## Tips for Success

### ✅ DO

- Start with small payload (100 records) to verify setup
- Wait for tests to complete (don't interrupt)
- Check results after each run
- Monitor K6 VM memory during large tests
- Document your VM configurations

### ❌ DON'T

- Don't run multiple experiments simultaneously
- Don't change VM configuration during tests
- Don't interrupt full experiment runs
- Don't commit config.env with real credentials
- Don't skip the 120s wait after seeding

## Cheat Sheet

```bash
# Quick test (3 runs, 100 records)
./run_multiple_tests.sh 3 100

# Full experiment (all payload sizes)
./run_full_experiment.sh

# Generate seed data
echo <number> | python gen_income.py

# Aggregate results (PowerShell)
pwsh combine_detailed_results.ps1

# Check latest results
ls -lt results/ | head

# View JSON result
cat results/test_*.json | jq .

# Clear old results
rm results/test_*

# Test VM connection
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-ip> "echo OK"

# Check K6 version
k6 version

# Find low memory runs
for f in results/vmstat_K6_VM_*.log; do
  echo -n "$f: "; awk 'NR>2 {print $4}' "$f" | sort -n | head -1;
done
```

## Getting Help

1. **Check documentation**: 
   - [README.md](README.md) - Full documentation
   - [SETUP.md](SETUP.md) - Detailed setup guide
   - [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) - Common issues

2. **Look at examples**:
   - Review existing test results in `results/`
   - Check notebook: `cache_performance_eda.ipynb`

3. **Debug**:
   ```bash
   # Verbose mode
   bash -x run_multiple_tests.sh 3 100
   
   # Check logs
   tail -f results/*.log
   ```

## What's Next?

Once you're comfortable:

1. 📚 Read [ARCHITECTURE.md](ARCHITECTURE.md) to understand the system
2. 🔬 Read [docs/ANALYSIS_GUIDE.md](docs/ANALYSIS_GUIDE.md) for analysis techniques
3. 🎯 Customize test parameters in `test_apdex.js`
4. 📊 Create your own analysis in Jupyter notebooks
5. 🚀 Run full experiments and publish your findings!

---

**Time to first result: ~5 minutes** ⏱️  
**Time to full experiment: ~6-8 hours** ⏱️  
**Time to insights: ~30 minutes** 💡

Happy testing! 🎉

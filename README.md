# Cache Performance Testing Framework

Automated testing framework untuk mengukur performa caching pada aplikasi High Tide menggunakan K6 load testing dan APDEX scoring methodology.

## 📋 Deskripsi

Repository ini berisi framework untuk menjalankan eksperimen perbandingan performa antara:
- **No Cache**: Aplikasi tanpa caching
- **Cache HIT**: Request yang dilayani dari cache
- **Cache MISS**: Request yang tidak ditemukan di cache

Framework ini menggunakan K6 untuk load testing dan mengukur metrik performa termasuk response time, APDEX score, dan resource utilization.

## 🏗️ Struktur Repository

```
.
├── test_apdex.js                    # K6 test script dengan APDEX scoring
├── gen_income.py                    # Generator untuk seed data income
├── run_multiple_tests.sh            # Script untuk menjalankan multiple test runs
├── run_full_experiment.sh           # Script untuk full experiment sequence
├── combine_detailed_results.ps1     # PowerShell script untuk agregasi hasil
├── cache_performance_eda.ipynb      # Jupyter notebook untuk analisis data
├── reset_hightide.sql              # SQL script untuk reset database
├── config.env                       # Configuration file
├── seeds/                           # Folder berisi seed data SQL files
│   ├── seed_income_10_records.sql
│   ├── seed_income_100_records.sql
│   ├── seed_income_1000_records.sql
│   └── ...
└── results/                         # Folder berisi hasil testing
    ├── test_*.json                  # Individual test results
    ├── test_*.csv                   # CSV format results
    ├── detailed_all_tests_*.csv     # Aggregated results
    └── resource_snapshot_*.log      # Resource monitoring logs
```

## 🚀 Cara Menggunakan

### Prerequisites

1. **K6** - Load testing tool
   ```bash
   # Install K6
   sudo gpg -k
   sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
   echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" | sudo tee /etc/apt/sources.list.d/k6.list
   sudo apt-get update
   sudo apt-get install k6
   ```

2. **Python 3.x** - Untuk seed generation
3. **PostgreSQL** - Database
4. **SSH Access** - Ke VM target

### Konfigurasi

Edit file `config.env` dengan kredensial VM Anda:

```bash
# VM IP Addresses
VM_NO_CACHE="your-no-cache-vm-ip"
VM_CACHE="your-cache-vm-ip"
VM_CACHE_BACKUP="your-backup-cache-vm-ip"

# SSH Configuration
SSH_KEY="~/.ssh/id_ed25519"
SSH_USER="ubuntu"

# Database Configuration
DB_NAME="aisco_product_hightide"
DB_USER="postgres"
```

### Generate Seed Data

```bash
# Generate seed file untuk jumlah records tertentu
python gen_income.py
# Input: 1000 (untuk 1000 records)
# Output: seeds/seed_income_1000_records.sql
```

### Menjalankan Single Test

```bash
# Test dengan payload size tertentu, 10 runs
./run_multiple_tests.sh 10 1000
```

### Menjalankan Full Experiment

```bash
# Menjalankan eksperimen lengkap dengan berbagai payload sizes
./run_full_experiment.sh
```

Script ini akan:
1. Reset database pada semua VM
2. Seed data sesuai payload size
3. Wait 120 detik untuk application restart
4. Menjalankan test untuk endpoint `automatic` dan `income`
5. Monitoring resource usage per-run
6. Menyimpan hasil ke folder `results/`

### Analisis Hasil

1. **Agregasi Data**
   ```powershell
   # Windows PowerShell
   .\combine_detailed_results.ps1
   ```

2. **Exploratory Data Analysis**
   ```bash
   # Buka Jupyter notebook
   jupyter notebook cache_performance_eda.ipynb
   ```

## 📊 Metrik yang Diukur

### Performance Metrics
- **Response Time**: avg, min, max, median, P90, P95, P99
- **APDEX Score**: Application Performance Index (0-1)
  - T = 500ms (Satisfied threshold)
  - F = 1500ms (Frustrated threshold)
- **Cache Statistics**: Hit rate, improvement percentages

### Resource Metrics (Per VM)
- **Memory Usage**: Free memory (min, max, avg)
- **CPU Usage**: User, System, Idle, Wait
- **Data Points**: Number of monitoring samples

### APDEX Categories
- **Satisfied**: Response time ≤ 500ms
- **Tolerating**: 500ms < Response time ≤ 1500ms
- **Frustrated**: Response time > 1500ms

## 🔬 Payload Sizes Tested

Default payload sizes yang ditest:
- 10 records
- 100 records
- 500 records
- 1,000 records
- 2,000 records
- 4,000 records
- 8,000 records
- 16,000 records
- 32,000 records

## 📈 Load Testing Configuration

 Framework ini mendukung **2 konfigurasi load testing** untuk membandingkan performa cache pada kondisi berbeda:

### 1. Normal Load Profile (5 VUs)
```javascript
stages: [
  { duration: '15s', target: 5 },   // Ramp-up to 5 VUs
  { duration: '1m', target: 5 },    // Sustained at 5 VUs
  { duration: '15s', target: 0 },   // Ramp-down
]
```
- **Use Case**: Typical/normal application load
- **Duration**: ~1.5 minutes per test
- **Purpose**: Baseline cache performance measurement

### 2. High Load Profile (50 VUs)
```javascript
stages: [
  { duration: '30s', target: 20 },  // Ramp-up phase 1
  { duration: '1m', target: 20 },   // Sustained phase 1
  { duration: '30s', target: 50 },  // Ramp-up phase 2
  { duration: '1m', target: 50 },   // Sustained phase 2
  { duration: '30s', target: 0 },   // Ramp-down
]
```
- **Use Case**: Peak/high traffic scenarios
- **Duration**: ~4 minutes per test
- **Purpose**: Cache effectiveness under heavy load

### Experimental Design

Untuk analisis komprehensif, **jalankan kedua konfigurasi** untuk setiap payload size:

1. **Normal Load Tests** (5 VUs):
   - Ukur baseline performance
   - Evaluasi cache improvement pada normal traffic
   - 10 runs per endpoint × 2 endpoints = 20 tests per payload

2. **High Load Tests** (50 VUs):
   - Ukur scalability dan cache effectiveness
   - Identifikasi bottleneck pada high concurrency
   - 10 runs per endpoint × 2 endpoints = 20 tests per payload

**Total per payload size**: 40 tests (20 normal + 20 high load)

## 🗂️ Output Files

### Test Results
- `test_<size>_records_<size>_<endpoint>_run<n>_<timestamp>.json` - Detailed metrics
- `test_<size>_records_<size>_<endpoint>_run<n>_<timestamp>.csv` - CSV format

### Aggregated Results
- `detailed_all_tests_<timestamp>.csv` - Combined data dari semua test runs

### Resource Monitoring
- `vmstat_<VM>_<payload>_<endpoint>_run<n>.log` - Continuous monitoring per run
- `resource_snapshot_<payload>_<endpoint>.log` - Snapshots sebelum/sesudah test

## 🛠️ Troubleshooting

### OOM (Out of Memory) Issues
Jika K6 VM mengalami OOM:
1. Check minimum free memory per run:
   ```bash
   for f in results/vmstat_K6_VM_*.log; do
     echo -n "$f: "; awk 'NR>2 {print $4}' "$f" | sort -n | head -1;
   done
   ```
2. Reduce VU count di `test_apdex.js`
3. Increase VM memory

### Database Connection Issues
```bash
# Test connection
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-ip> "psql -U postgres -d aisco_product_hightide -c 'SELECT 1;'"
```

### Cache Not Working
```bash
# Verify nginx cache configuration
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-ip> "nginx -T | grep -A 10 proxy_cache"

# Clear cache manually
ssh -i ~/.ssh/id_ed25519 ubuntu@<vm-ip> "sudo rm -rf /var/cache/nginx/* /var/run/nginx-cache/*"
```

## 📝 Notes

- Setiap test run membutuhkan waktu ~1.5-3 menit tergantung load profile
- Wait time 120 detik setelah seeding penting untuk application warm-up
- Resource monitoring berjalan setiap 5 detik selama test
- Hasil test disimpan dengan timestamp untuk tracking

## 👥 Contributors

- Gilang (Skripsi - Cache Performance Analysis)

## 📄 License

Academic Project - Universitas Indonesia

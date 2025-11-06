# Architecture Documentation

## System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      K6 Load Testing VM                     │
│  ┌──────────────┐  ┌──────────────┐  ┌─────────────────┐  │
│  │ test_apdex.js│  │ Shell Scripts│  │ Resource Monitor│  │
│  └──────────────┘  └──────────────┘  └─────────────────┘  │
└───────────────────────┬─────────────────────────────────────┘
                        │ HTTPS Requests
        ┌───────────────┼───────────────┐
        │               │               │
        ▼               ▼               ▼
┌───────────────┐ ┌───────────────┐ ┌───────────────┐
│   VM No-Cache │ │  VM Cache (1) │ │  VM Cache (2) │
│               │ │               │ │               │
│ ┌───────────┐ │ │ ┌───────────┐ │ │ ┌───────────┐ │
│ │   Nginx   │ │ │ │   Nginx   │ │ │ │   Nginx   │ │
│ │ (No Cache)│ │ │ │ (w/ Cache)│ │ │ │ (w/ Cache)│ │
│ └─────┬─────┘ │ │ └─────┬─────┘ │ │ └─────┬─────┘ │
│       │       │ │       │       │ │       │       │
│ ┌─────▼─────┐ │ │ ┌─────▼─────┐ │ │ ┌─────▼─────┐ │
│ │ Spring    │ │ │ │ Spring    │ │ │ │ Spring    │ │
│ │ Boot App  │ │ │ │ Boot App  │ │ │ │ Boot App  │ │
│ └─────┬─────┘ │ │ └─────┬─────┘ │ │ └─────┬─────┘ │
│       │       │ │       │       │ │       │       │
│ ┌─────▼─────┐ │ │ ┌─────▼─────┐ │ │ ┌─────▼─────┐ │
│ │PostgreSQL │ │ │ │PostgreSQL │ │ │ │PostgreSQL │ │
│ └───────────┘ │ │ └───────────┘ │ │ └───────────┘ │
└───────────────┘ └───────────────┘ └───────────────┘
```

## Component Description

### 1. K6 Load Testing VM

**Purpose**: Generate load, measure performance, collect metrics

**Components**:
- **test_apdex.js**: K6 test script with APDEX methodology
  - Sends HTTP requests to all 3 VMs
  - Categorizes responses (Satisfied/Tolerating/Frustrated)
  - Detects cache HIT/MISS via headers
  - Collects detailed metrics

- **Shell Scripts**:
  - `run_multiple_tests.sh`: Orchestrates test runs
  - `run_full_experiment.sh`: Full experiment automation
  - Handles database seeding, cache clearing, monitoring

- **Resource Monitor**:
  - `vmstat` process monitoring memory/CPU
  - Runs continuously during tests
  - Saves logs for analysis

### 2. Target VMs (3 instances)

#### VM No-Cache
- **Nginx**: Configured WITHOUT proxy_cache
- **Purpose**: Baseline performance measurement
- **Every request**: Hits application → database

#### VM Cache (1)
- **Nginx**: Configured WITH proxy_cache
- **Purpose**: Measure Cache HIT performance
- **Cache warm-up**: Done before each test run
- **Expected**: Mostly HIT responses

#### VM Cache (2)
- **Nginx**: Configured WITH proxy_cache
- **Purpose**: Measure Cache MISS performance
- **Cache cleared**: Before each test run
- **Expected**: All MISS responses (first request)

## Data Flow

### Test Execution Flow

```
1. PREPARATION
   ├── Reset databases on all VMs
   ├── Seed test data (income records)
   └── Wait 120s for application restart

2. TEST EXECUTION (per endpoint)
   ├── Clear cache on Cache VMs
   ├── Warm-up Cache VM (1) - 3 requests
   ├── Start resource monitoring
   │
   ├── FOR each run (1 to N):
   │   ├── K6 sends load to all 3 VMs simultaneously
   │   │   ├── VM No-Cache: Always fresh from DB
   │   │   ├── VM Cache (1): Should get HITs
   │   │   └── VM Cache (2): Force MISS with cache_bust
   │   │
   │   ├── Collect metrics per VM:
   │   │   ├── Response times (avg, P90, P95, P99)
   │   │   ├── APDEX categories count
   │   │   ├── Cache status (HIT/MISS)
   │   │   └── Resource usage (CPU, memory)
   │   │
   │   ├── Save results:
   │   │   ├── JSON: Detailed metrics
   │   │   ├── CSV: Tabular format
   │   │   └── Logs: Resource monitoring
   │   │
   │   └── Wait 10s before next run
   │
   └── Stop resource monitoring

3. AGGREGATION
   ├── Combine all JSON files
   ├── Parse resource logs
   ├── Calculate statistics
   └── Generate CSV for analysis
```

### Caching Strategy

```
Request Flow - No Cache VM:
Client → Nginx → App → Database → App → Nginx → Client
         (no cache)

Request Flow - Cache HIT:
Client → Nginx (cached) → Client
         (returns cached response)

Request Flow - Cache MISS:
Client → Nginx → App → Database → App → Nginx (stores in cache) → Client
```

## Key Metrics

### Performance Metrics

1. **Response Time Percentiles**
   - Average (mean)
   - Median (P50)
   - P90: 90% of requests faster than this
   - P95: 95% of requests faster than this
   - P99: 99% of requests faster than this

2. **APDEX Score** (0 to 1)
   ```
   APDEX = (Satisfied + Tolerating/2) / Total Requests
   
   Where:
   - Satisfied: response_time ≤ T (500ms)
   - Tolerating: T < response_time ≤ 4T (2000ms)
   - Frustrated: response_time > 4T (2000ms)
   ```

3. **Cache Statistics**
   - Hit Rate: (Hits / Total) × 100%
   - Improvement: ((No-Cache - Cache-HIT) / No-Cache) × 100%

### Resource Metrics

1. **Memory Usage**
   - Free memory (MB)
   - Used memory (MB)
   - Swap usage

2. **CPU Usage**
   - User time (%)
   - System time (%)
   - Idle time (%)
   - I/O wait (%)

## Load Testing Configuration

### Dual Configuration Approach

The framework supports **two load testing profiles** to comprehensively evaluate cache performance:

#### Profile 1: Normal Load (5 VUs)
```javascript
[
  { duration: '15s', target: 5 },   // Ramp-up to 5 VUs
  { duration: '1m', target: 5 },    // Sustain 5 VUs
  { duration: '15s', target: 0 }    // Ramp-down
]
Total: 1m 45s per run
```

**Characteristics**:
- Simulates typical application load
- Lower concurrency for baseline measurements
- Suitable for all payload sizes
- Focus on individual request performance

**Use For**:
- Baseline cache performance
- Response time analysis
- APDEX score under normal conditions

#### Profile 2: High Load (50 VUs)
```javascript
[
  { duration: '30s', target: 20 },  // Ramp-up to 20 VUs
  { duration: '1m', target: 20 },   // Sustain 20 VUs
  { duration: '30s', target: 50 },  // Ramp-up to 50 VUs
  { duration: '1m', target: 50 },   // Sustain 50 VUs
  { duration: '30s', target: 0 }    // Ramp-down
]
Total: 4m per run
```

**Characteristics**:
- Simulates peak traffic scenarios
- High concurrency testing
- Tests cache effectiveness under pressure
- Identifies scalability bottlenecks

**Use For**:
- Peak load performance
- Cache scalability analysis
- Stress testing
- Concurrent request handling

### Experimental Design

**Recommended Workflow**:

1. **Phase 1: Normal Load Experiments**
   - Run all payload sizes (10 to 32K) with 5 VUs
   - Collect baseline metrics
   - 10 runs × 2 endpoints × 9 payload sizes = 180 tests
   - Duration: ~6-8 hours

2. **Phase 2: High Load Experiments**
   - Run all payload sizes (10 to 32K) with 50 VUs
   - Collect high-load metrics
   - 10 runs × 2 endpoints × 9 payload sizes = 180 tests
   - Duration: ~12-15 hours

3. **Analysis: Compare Both Profiles**
   - Cache improvement: Normal vs High Load
   - Scalability: How does cache help under pressure?
   - Bottleneck identification: Where does performance degrade?

**Total Tests**: 360 (180 normal + 180 high load)

## Database Schema

### Key Tables

```sql
-- Chart of Account
chartofaccount_comp (id)
chartofaccount_impl (id, code, name, description, isvisible)

-- Programs
program_comp (idprogram, name, description, executiondate, ...)
program_activity (idprogram)

-- Financial Reports (base)
financialreport_comp (id, amount, datestamp, description, coa_id, program_idprogram)
financialreport_impl (id)

-- Income-specific
financialreport_income (id, paymentmethod)
```

### Seeding Strategy

1. Insert COA records (5 accounts)
2. Insert Program records (3 programs)
3. Insert Financial Report Component (N records)
4. Insert Financial Report Implementation (N records)
5. Insert Income-specific data (N records)

## API Endpoints Tested

### 1. Automatic Report (Aggregate)
```
GET /call/automatic-report-twolevel/list
```
- Complex aggregation queries
- Multiple joins
- Group by operations
- Heavy computation

### 2. Income List (High Payload)
```
GET /call/income/list
```
- Large result set
- Multiple table joins
- Payload size controlled by seed data

## Cache Detection Logic

The test script detects cache HIT/MISS using:

```javascript
1. X-Cache-Status header
   - HIT, MISS, BYPASS, EXPIRED, STALE, etc.

2. Age header
   - Age > 0 → Cache HIT
   - Age = 0 or missing → Cache MISS

3. X-Cache header
   - "HIT" string → Cache HIT
   - "MISS" string → Cache MISS
```

## File Naming Convention

### Test Results
```
test_<payload>_records_<payload>_<endpoint>_run<n>_<timestamp>.json
test_<payload>_records_<payload>_<endpoint>_run<n>_<timestamp>.csv

Example:
test_1000_records_1000_income_run5_20251104_203431.json
```

### Resource Monitoring
```
vmstat_<VM_NAME>_<payload>_<endpoint>_run<n>.log
resource_snapshot_<payload>_<endpoint>.log

Example:
vmstat_K6_VM_1000_income_run5.log
resource_snapshot_1000_automatic.log
```

### Seed Files
```
seed_income_<count>_records.sql

Example:
seed_income_1000_records.sql
```

## Performance Considerations

### Memory Management
- K6 VM needs sufficient RAM (4GB+ recommended)
- Adaptive VU scaling for large payloads
- Continuous monitoring to detect OOM

### Network
- Tests run over HTTPS
- Network latency included in measurements
- SSL/TLS overhead accounted for

### Database
- PostgreSQL connection pooling
- Indexes on frequently queried columns
- Vacuum/analyze after seeding

### Cache Configuration
- 10MB cache zone (keys_zone)
- 1GB max cache size
- 60 minute inactive timeout
- Background updates enabled

## Monitoring & Observability

### Real-time Monitoring
- `vmstat` captures every 5 seconds during test
- Tracks: memory, swap, I/O, CPU
- Identifies bottlenecks and OOM conditions

### Post-test Analysis
- Aggregate multiple runs for statistical significance
- Compare No-Cache vs Cache HIT vs Cache MISS
- Identify performance trends across payload sizes
- Correlation between payload size and performance

## Security Considerations

- SSH key-based authentication
- No passwords in config files
- Private keys not committed to repo
- Database credentials in environment file
- HTTPS for all API calls

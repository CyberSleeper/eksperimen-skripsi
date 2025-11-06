# Analysis Guide

Panduan untuk menganalisis hasil testing menggunakan berbagai tools.

## 1. Aggregate Results with PowerShell

### Menjalankan Script Agregasi

```powershell
# Windows PowerShell
cd D:\Kuliah\TA\testing\skripsi_gilang_eksperimen
.\combine_detailed_results.ps1
```

### Output yang Dihasilkan

Script ini akan menghasilkan file:
```
results/detailed_all_tests_<timestamp>.csv
```

File ini berisi:
- Semua test runs dalam satu file
- 160+ kolom dengan detailed metrics
- Resource monitoring data (4 VMs)
- Cache statistics
- APDEX scores dan kategorisasi

### Kolom Penting

**Test Configuration**:
- `TestRunID`: Identifier unique untuk setiap test
- `Timestamp`: Waktu eksekusi
- `Endpoint`: automatic atau income
- `PayloadSize`: Jumlah records (10, 100, 1000, dst)
- `RunNumber`: Run ke-berapa (1-10)

**No Cache Metrics**:
- `NoCache_AvgResponseTime`: Rata-rata response time tanpa cache
- `NoCache_APDEX_Score`: APDEX score (0-1)
- `NoCache_P90`, `NoCache_P95`, `NoCache_P99`: Percentiles
- `NoCache_Satisfied`, `NoCache_Tolerating`, `NoCache_Frustrated`: Counts

**Cache HIT Metrics**:
- `CacheHit_AvgResponseTime`: Rata-rata response time dengan cache HIT
- `CacheHit_APDEX_Score`: APDEX score
- `CacheHit_P90`, `CacheHit_P95`, `CacheHit_P99`: Percentiles
- `CacheHit_Satisfied`, `CacheHit_Tolerating`, `CacheHit_Frustrated`: Counts

**Cache MISS Metrics**:
- `CacheMiss_AvgResponseTime`: Rata-rata response time dengan cache MISS
- `CacheMiss_APDEX_Score`: APDEX score
- Similar percentiles dan category counts

**Cache Statistics**:
- `CacheHitRate`: Persentase cache hits (%)
- `Improvement_HIT_vs_NoCache`: Improvement dari cache (%)
- `Improvement_HIT_vs_MISS`: Perbedaan HIT vs MISS (%)

**Resource Metrics (per VM)**:
- `K6_MinFreeMem`, `K6_AvgFreeMem`, `K6_MaxFreeMem`: Memory K6 VM
- `K6_AvgCPU_User`, `K6_AvgCPU_System`, `K6_AvgCPU_Idle`: CPU K6 VM
- Similar metrics untuk `NoCache`, `CacheHit`, `CacheMiss` VMs

## 2. Exploratory Data Analysis (EDA) with Jupyter

### Setup Jupyter Notebook

```bash
# Install dependencies (jika belum)
pip install jupyter pandas numpy matplotlib seaborn plotly

# Start Jupyter
jupyter notebook cache_performance_eda.ipynb
```

### Analysis Steps in Notebook

#### Step 1: Load Data
```python
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

# Load aggregated results
df = pd.read_csv('results/detailed_all_tests_20251105_083402.csv')
print(df.shape)
print(df.columns)
```

#### Step 2: Basic Statistics
```python
# Summary statistics
df.describe()

# Group by payload size
df.groupby('PayloadSize')[['NoCache_AvgResponseTime', 
                            'CacheHit_AvgResponseTime']].mean()

# Group by endpoint
df.groupby('Endpoint')[['NoCache_APDEX_Score', 
                         'CacheHit_APDEX_Score']].mean()
```

#### Step 3: Visualizations

**Response Time by Payload Size**
```python
import matplotlib.pyplot as plt

plt.figure(figsize=(12, 6))
for endpoint in df['Endpoint'].unique():
    subset = df[df['Endpoint'] == endpoint]
    grouped = subset.groupby('PayloadSize')[['NoCache_AvgResponseTime', 
                                               'CacheHit_AvgResponseTime']].mean()
    
    plt.plot(grouped.index, grouped['NoCache_AvgResponseTime'], 
             marker='o', label=f'{endpoint} - No Cache')
    plt.plot(grouped.index, grouped['CacheHit_AvgResponseTime'], 
             marker='s', label=f'{endpoint} - Cache HIT')

plt.xlabel('Payload Size (records)')
plt.ylabel('Average Response Time (ms)')
plt.title('Response Time vs Payload Size')
plt.legend()
plt.grid(True)
plt.xscale('log')
plt.show()
```

**APDEX Score Comparison**
```python
fig, axes = plt.subplots(1, 2, figsize=(14, 6))

# No Cache APDEX
df.groupby('PayloadSize')['NoCache_APDEX_Score'].mean().plot(
    kind='bar', ax=axes[0], color='coral'
)
axes[0].set_title('No Cache APDEX Score by Payload Size')
axes[0].set_ylabel('APDEX Score')
axes[0].axhline(y=0.94, color='green', linestyle='--', label='Excellent')
axes[0].axhline(y=0.85, color='yellow', linestyle='--', label='Good')
axes[0].axhline(y=0.70, color='orange', linestyle='--', label='Fair')
axes[0].legend()

# Cache HIT APDEX
df.groupby('PayloadSize')['CacheHit_APDEX_Score'].mean().plot(
    kind='bar', ax=axes[1], color='skyblue'
)
axes[1].set_title('Cache HIT APDEX Score by Payload Size')
axes[1].set_ylabel('APDEX Score')
axes[1].axhline(y=0.94, color='green', linestyle='--', label='Excellent')
axes[1].axhline(y=0.85, color='yellow', linestyle='--', label='Good')
axes[1].axhline(y=0.70, color='orange', linestyle='--', label='Fair')
axes[1].legend()

plt.tight_layout()
plt.show()
```

**Cache Performance Improvement**
```python
plt.figure(figsize=(10, 6))
improvement = df.groupby('PayloadSize')['Improvement_HIT_vs_NoCache'].mean()
improvement.plot(kind='bar', color='green')
plt.xlabel('Payload Size (records)')
plt.ylabel('Improvement (%)')
plt.title('Cache Performance Improvement vs No Cache')
plt.grid(True, axis='y')
plt.show()
```

**Percentile Distribution**
```python
payload = 1000  # Select specific payload
subset = df[df['PayloadSize'] == payload]

fig, ax = plt.subplots(figsize=(10, 6))
x = ['P50', 'P90', 'P95', 'P99']
no_cache = [subset['NoCache_MedianResponseTime'].mean(),
            subset['NoCache_P90'].mean(),
            subset['NoCache_P95'].mean(),
            subset['NoCache_P99'].mean()]
cache_hit = [subset['CacheHit_MedianResponseTime'].mean(),
             subset['CacheHit_P90'].mean(),
             subset['CacheHit_P95'].mean(),
             subset['CacheHit_P99'].mean()]

width = 0.35
x_pos = range(len(x))
ax.bar([p - width/2 for p in x_pos], no_cache, width, label='No Cache')
ax.bar([p + width/2 for p in x_pos], cache_hit, width, label='Cache HIT')

ax.set_xlabel('Percentile')
ax.set_ylabel('Response Time (ms)')
ax.set_title(f'Response Time Percentiles (Payload: {payload} records)')
ax.set_xticks(x_pos)
ax.set_xticklabels(x)
ax.legend()
plt.show()
```

**Resource Usage Analysis**
```python
fig, axes = plt.subplots(2, 2, figsize=(14, 10))

# K6 VM Memory
df.groupby('PayloadSize')[['K6_MinFreeMem', 'K6_AvgFreeMem']].mean().plot(
    ax=axes[0, 0], marker='o'
)
axes[0, 0].set_title('K6 VM Memory Usage')
axes[0, 0].set_ylabel('Free Memory (KB)')

# K6 VM CPU
df.groupby('PayloadSize')[['K6_AvgCPU_User', 'K6_AvgCPU_System']].mean().plot(
    kind='bar', stacked=True, ax=axes[0, 1]
)
axes[0, 1].set_title('K6 VM CPU Usage')
axes[0, 1].set_ylabel('CPU %')

# No Cache VM Memory
df.groupby('PayloadSize')['NoCache_AvgFreeMem'].mean().plot(
    kind='bar', ax=axes[1, 0], color='coral'
)
axes[1, 0].set_title('No Cache VM - Free Memory')
axes[1, 0].set_ylabel('Free Memory (KB)')

# Cache HIT VM Memory
df.groupby('PayloadSize')['CacheHit_AvgFreeMem'].mean().plot(
    kind='bar', ax=axes[1, 1], color='skyblue'
)
axes[1, 1].set_title('Cache HIT VM - Free Memory')
axes[1, 1].set_ylabel('Free Memory (KB)')

plt.tight_layout()
plt.show()
```

**APDEX Category Distribution**
```python
payload = 1000
subset = df[df['PayloadSize'] == payload]

categories = ['Satisfied', 'Tolerating', 'Frustrated']
no_cache_counts = [subset['NoCache_Satisfied'].mean(),
                   subset['NoCache_Tolerating'].mean(),
                   subset['NoCache_Frustrated'].mean()]
cache_hit_counts = [subset['CacheHit_Satisfied'].mean(),
                    subset['CacheHit_Tolerating'].mean(),
                    subset['CacheHit_Frustrated'].mean()]

fig, axes = plt.subplots(1, 2, figsize=(12, 5))

axes[0].pie(no_cache_counts, labels=categories, autopct='%1.1f%%',
            colors=['green', 'yellow', 'red'])
axes[0].set_title(f'No Cache - APDEX Distribution\n(Payload: {payload})')

axes[1].pie(cache_hit_counts, labels=categories, autopct='%1.1f%%',
            colors=['green', 'yellow', 'red'])
axes[1].set_title(f'Cache HIT - APDEX Distribution\n(Payload: {payload})')

plt.tight_layout()
plt.show()
```

#### Step 4: Statistical Tests

**T-test for Significance**
```python
from scipy import stats

# Compare response times
no_cache = df[df['PayloadSize'] == 1000]['NoCache_AvgResponseTime']
cache_hit = df[df['PayloadSize'] == 1000]['CacheHit_AvgResponseTime']

t_stat, p_value = stats.ttest_ind(no_cache, cache_hit)
print(f"T-statistic: {t_stat:.4f}")
print(f"P-value: {p_value:.4f}")

if p_value < 0.05:
    print("Difference is statistically significant!")
else:
    print("Difference is NOT statistically significant.")
```

**Correlation Analysis**
```python
# Correlation between payload size and response time
correlation = df[['PayloadSize', 'NoCache_AvgResponseTime', 
                  'CacheHit_AvgResponseTime']].corr()
print(correlation)

# Heatmap
sns.heatmap(correlation, annot=True, cmap='coolwarm', center=0)
plt.title('Correlation Matrix')
plt.show()
```

## 3. Command Line Analysis

### Quick Stats with Command Line

**Count test runs**
```bash
ls results/test_*.json | wc -l
```

**Find tests with lowest K6 RAM**
```bash
for f in results/vmstat_K6_VM_*.log; do
  echo -n "$f: "; awk 'NR>2 {print $4}' "$f" | sort -n | head -1;
done
```

**Extract average response times**
```bash
jq -r '[.no_cache.response_times.avg, .cache_hit.response_times.avg] | @csv' \
  results/test_*_income_run1_*.json
```

**Calculate cache hit rate**
```bash
jq -r '.cache_statistics.hit_rate' results/test_*_run1_*.json
```

## 4. Excel/Google Sheets Analysis

### Import CSV

1. Open Excel/Google Sheets
2. Import `detailed_all_tests_*.csv`
3. Enable filters on header row

### Useful Formulas

**Average response time by payload**
```excel
=AVERAGEIF(PayloadSize, 1000, NoCache_AvgResponseTime)
```

**Improvement percentage**
```excel
=((NoCache_AvgResponseTime - CacheHit_AvgResponseTime) / NoCache_AvgResponseTime) * 100
```

**APDEX Score from categories**
```excel
=(Satisfied + Tolerating/2) / (Satisfied + Tolerating + Frustrated)
```

### Pivot Tables

Create pivot table with:
- Rows: PayloadSize, Endpoint
- Values: Average of NoCache_AvgResponseTime, CacheHit_AvgResponseTime
- Filters: RunNumber (to see specific runs)

## 5. Key Metrics to Analyze

### Performance Comparison
- [ ] Average response time: No Cache vs Cache HIT
- [ ] Percentiles (P90, P95, P99): Tail latency analysis
- [ ] APDEX scores: User satisfaction metrics
- [ ] Improvement percentage: Cache effectiveness

### Scalability Analysis
- [ ] Response time vs Payload size: Growth pattern
- [ ] APDEX score vs Payload size: Degradation point
- [ ] Resource usage vs Payload size: Bottlenecks

### Cache Effectiveness
- [ ] Hit rate: Percentage of successful cache hits
- [ ] HIT vs MISS comparison: Cache overhead
- [ ] Time saved: Absolute improvement in ms

### Resource Utilization
- [ ] Memory trends: OOM detection
- [ ] CPU usage: Processing bottlenecks
- [ ] Correlation with performance: Resource impact

## 6. Reporting Template

### Executive Summary
1. Total tests run
2. Payload sizes tested
3. Average improvement with cache
4. Key findings

### Detailed Analysis
1. Response time analysis
2. APDEX score analysis
3. Cache effectiveness
4. Resource utilization
5. Scalability insights

### Recommendations
1. Optimal cache configuration
2. Payload size limits
3. Resource allocation needs
4. Performance optimization opportunities

## 7. Export for Thesis/Paper

### Generate Charts
- Export matplotlib figures as PNG/PDF (300 DPI)
- Use consistent color scheme
- Add proper labels and legends

### Tables
- Format significant digits (2-3 decimal places)
- Include sample size (N)
- Add standard deviation/confidence intervals

### Statistical Results
- Report p-values for significance tests
- Include effect sizes
- Mention test assumptions and validity

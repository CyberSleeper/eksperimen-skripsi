# Dual Configuration Testing Guide

## Overview

This framework supports **two load testing configurations** to provide comprehensive cache performance analysis under different load conditions.

## Two Load Profiles

### Profile 1: Normal Load (5 VUs)
- **Virtual Users**: 5
- **Duration**: ~1.5 minutes per test
- **Purpose**: Baseline performance, typical application load
- **Scenario**: Regular business hours, normal user activity

### Profile 2: High Load (50 VUs)
- **Virtual Users**: Up to 50
- **Duration**: ~4 minutes per test
- **Purpose**: Peak performance, stress testing
- **Scenario**: Peak hours, promotional events, high traffic

## Why Test Both Configurations?

### 1. Different Cache Behavior
- **Normal Load**: Cache benefits may be less pronounced
- **High Load**: Cache shows significant performance improvements
- **Insight**: Understand when cache provides maximum value

### 2. Scalability Analysis
- **Normal Load**: Baseline scalability
- **High Load**: Identify bottlenecks and limits
- **Insight**: Determine optimal payload sizes for production

### 3. Concurrency Effects
- **Normal Load**: Sequential-like behavior
- **High Load**: Concurrent request handling
- **Insight**: Cache effectiveness under concurrent access

### 4. Resource Utilization
- **Normal Load**: Lower CPU/memory usage
- **High Load**: Resource constraints visible
- **Insight**: Infrastructure requirements planning

## Experimental Workflow

### Step 1: Normal Load Testing

```bash
# Edit test_apdex.js - uncomment NORMAL LOAD profile
# Comment out HIGH LOAD profile

# Run full experiment with normal load
./run_full_experiment.sh

# Results will be saved with normal load metrics
# Expected duration: ~6-8 hours for all payload sizes
```

### Step 2: High Load Testing

```bash
# Edit test_apdex.js - uncomment HIGH LOAD profile
# Comment out NORMAL LOAD profile

# Run full experiment with high load
./run_full_experiment.sh

# Results will be saved with high load metrics
# Expected duration: ~12-15 hours for all payload sizes
```

### Step 3: Aggregate and Compare

```powershell
# After both experiments complete
.\combine_detailed_results.ps1

# This creates a CSV with all test runs
# You can filter by load profile during analysis
```

## Switching Between Profiles

### In test_apdex.js

```javascript
function getStages() {
  // UNCOMMENT ONE PROFILE AT A TIME
  
  // NORMAL LOAD (5 VUs)
  return [
    { duration: '15s', target: 5 },
    { duration: '1m', target: 5 },
    { duration: '15s', target: 0 },
  ];

  // HIGH LOAD (50 VUs)
  // return [
  //   { duration: '30s', target: 20 },
  //   { duration: '1m', target: 20 },
  //   { duration: '30s', target: 50 },
  //   { duration: '1m', target: 50 },
  //   { duration: '30s', target: 0 },
  // ];
}
```

## Expected Results by Configuration

### Normal Load (5 VUs)

**No Cache**:
- Response times: Moderate
- APDEX: Good to Fair (0.70-0.90)
- CPU: Low usage
- Memory: Stable

**Cache HIT**:
- Response times: Low
- APDEX: Excellent (>0.90)
- CPU: Very low
- Improvement: 30-50% faster

**Cache MISS**:
- Response times: Similar to No Cache
- APDEX: Good to Fair
- CPU: Moderate
- Overhead: Minimal

### High Load (50 VUs)

**No Cache**:
- Response times: High, variable
- APDEX: Fair to Poor (0.50-0.80)
- CPU: High usage
- Memory: Increased consumption
- Queuing delays visible

**Cache HIT**:
- Response times: Significantly lower
- APDEX: Excellent to Good (>0.80)
- CPU: Moderate (cache serving)
- Improvement: 60-80% faster
- **Cache value clearly demonstrated**

**Cache MISS**:
- Response times: Similar to No Cache
- APDEX: Fair to Poor
- CPU: High usage
- Overhead: Cache population cost

## Analysis Scenarios

### Scenario 1: Cache Improvement by Load

**Question**: Does cache provide more benefit under high load?

**Method**:
```python
# Compare improvement percentages
normal_improvement = (normal_nocache - normal_cachehit) / normal_nocache * 100
high_improvement = (high_nocache - high_cachehit) / high_nocache * 100

# Expected: high_improvement > normal_improvement
```

### Scenario 2: Scalability Comparison

**Question**: How does each scenario scale with payload size?

**Method**:
```python
# Plot response time vs payload size for each config
# Compare slopes:
# - Steeper slope = worse scalability
# - Cache should have flatter slope
```

### Scenario 3: APDEX Under Load

**Question**: How does user satisfaction change with load?

**Method**:
```python
# Compare APDEX scores:
# Normal Load: Should be generally higher
# High Load: Shows where cache maintains quality
```

### Scenario 4: Resource Efficiency

**Question**: Does cache reduce resource consumption?

**Method**:
```python
# Compare CPU/memory usage:
# Cache should reduce DB queries → lower resource usage
# Especially visible under high load
```

## Naming Convention for Results

### Distinguish Between Configurations

**Option 1: Separate Folders**
```
results/
├── normal_load/
│   ├── test_100_records_100_automatic_run1_*.json
│   └── ...
└── high_load/
    ├── test_100_records_100_automatic_run1_*.json
    └── ...
```

**Option 2: File Naming**
```
test_100_records_100_automatic_normalload_run1_*.json
test_100_records_100_automatic_highload_run1_*.json
```

**Option 3: Metadata in JSON**
```json
{
  "test_configuration": {
    "load_profile": "normal",  // or "high"
    "max_vus": 5,             // or 50
    ...
  }
}
```

## Timeline Estimation

### Normal Load Experiments
- Payload sizes: 9 (10, 100, 500, 1K, 2K, 4K, 8K, 16K, 32K)
- Endpoints: 2 (automatic, income)
- Runs: 10 per endpoint
- Time per run: ~1.5 min
- Total: 9 × 2 × 10 × 1.5 min = **270 minutes (~4.5 hours)**
- With overhead: **6-8 hours**

### High Load Experiments
- Same payload sizes and endpoints
- Time per run: ~4 min
- Total: 9 × 2 × 10 × 4 min = **720 minutes (~12 hours)**
- With overhead: **12-15 hours**

### Total Experiment Time
- **Combined**: ~18-23 hours
- **Recommendation**: Run overnight or over weekend

## Comparative Metrics Table

| Metric | Normal Load | High Load | Insight |
|--------|-------------|-----------|---------|
| Cache Improvement | Moderate (30-50%) | High (60-80%) | Cache more valuable at high load |
| Response Time Variance | Low | High | High load shows more variability |
| APDEX Score | Higher overall | Lower (No Cache) | Cache maintains quality under pressure |
| Resource Usage | Lower | Higher | High load stresses resources |
| Bottlenecks | Less visible | Clearly identified | Capacity planning insights |

## Best Practices

### 1. Document Configuration
- Always note which profile was used
- Include in test metadata
- Separate result directories

### 2. Consistent Environment
- Same VMs for both profiles
- Same database state (reset + seed)
- Same time of day (if possible)

### 3. Sequential Execution
- Don't mix configurations in one experiment
- Complete all normal load tests first
- Then complete all high load tests

### 4. Resource Monitoring
- Monitor K6 VM carefully during high load
- Check for OOM conditions
- Adjust VU count if needed

### 5. Analysis
- Compare like-with-like (same payload, different load)
- Identify trends across load profiles
- Document unexpected behaviors

## Common Questions

### Q: Which configuration should I run first?
**A**: Start with **Normal Load** - it's faster and helps validate setup.

### Q: Can I skip one configuration?
**A**: Not recommended. Both provide valuable insights:
- Normal Load: Baseline performance
- High Load: Cache effectiveness demonstration

### Q: What if high load causes OOM?
**A**: The framework has adaptive VU scaling. If still problematic:
1. Reduce max VUs in test_apdex.js
2. Use smaller payload sizes for high load
3. Increase K6 VM memory

### Q: How do I compare the two configurations?
**A**: Use the Jupyter notebook with filters:
```python
normal_df = df[df['MaxVUs'] == 5]
high_df = df[df['MaxVUs'] == 50]

# Then compare metrics
```

### Q: Should results be in separate files?
**A**: Recommended - easier to manage and analyze separately. But aggregation script combines them.

## Thesis/Paper Implications

### Research Questions Addressed

1. **RQ1**: How effective is nginx caching?
   - **Answer**: Compare both load profiles

2. **RQ2**: When does cache provide maximum benefit?
   - **Answer**: High load shows greater improvement

3. **RQ3**: How does system scale with payload size?
   - **Answer**: Compare normal vs high load scalability

4. **RQ4**: What are resource requirements?
   - **Answer**: Resource metrics from both profiles

### Reporting Structure

```
Abstract
1. Introduction
2. Related Work
3. Methodology
   3.1 Experimental Design
       3.1.1 Normal Load Configuration (5 VUs)
       3.1.2 High Load Configuration (50 VUs)
   3.2 Metrics and Tools
4. Results
   4.1 Normal Load Results
   4.2 High Load Results
   4.3 Comparative Analysis
5. Discussion
6. Conclusion
```

## Example Analysis Code

```python
import pandas as pd
import matplotlib.pyplot as plt

# Load data
df = pd.read_csv('results/detailed_all_tests.csv')

# Separate by load profile (assuming you have this column)
normal = df[df['MaxVUs'] == 5]
high = df[df['MaxVUs'] == 50]

# Compare cache improvement
fig, axes = plt.subplots(1, 2, figsize=(14, 6))

# Normal Load
normal_grouped = normal.groupby('PayloadSize')['Improvement_HIT_vs_NoCache'].mean()
normal_grouped.plot(ax=axes[0], marker='o')
axes[0].set_title('Cache Improvement - Normal Load (5 VUs)')
axes[0].set_ylabel('Improvement (%)')

# High Load
high_grouped = high.groupby('PayloadSize')['Improvement_HIT_vs_NoCache'].mean()
high_grouped.plot(ax=axes[1], marker='o', color='orange')
axes[1].set_title('Cache Improvement - High Load (50 VUs)')
axes[1].set_ylabel('Improvement (%)')

plt.tight_layout()
plt.savefig('cache_improvement_comparison.png', dpi=300)
```

## Conclusion

Testing with both configurations provides:
- ✅ Comprehensive performance analysis
- ✅ Clear cache value demonstration
- ✅ Scalability insights
- ✅ Infrastructure planning data
- ✅ Stronger research findings

**Time investment**: ~20 hours total  
**Data gained**: 360 test runs with diverse conditions  
**Research value**: High - demonstrates cache effectiveness across scenarios

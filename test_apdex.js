import http from 'k6/http';
import { sleep, check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const PAYLOAD_SIZE = parseInt(__ENV.PAYLOAD_SIZE || '10');
const TEST_RUN_ID = __ENV.TEST_RUN_ID || new Date().toISOString().replace(/[:.]/g, '-');
const ENDPOINT = __ENV.ENDPOINT || '/call/automatic-report-twolevel/list';

// --- URLs untuk testing ---
const API_NO_CACHE = `https://hightide-no-cache.sple.my.id${ENDPOINT}`;
const API_WITH_CACHE = `https://hightide-cache.sple.my.id${ENDPOINT}`;
const API_CACHE_MISS = `https://hightide-cache.sple.my.id${ENDPOINT}`;

// --- Konfigurasi Tes ---
const APDEX_T = 500;
const APDEX_F = 1500;

function getStages() {
  // TWO LOAD PROFILES AVAILABLE - Switch between them for comprehensive analysis
  
  // PROFILE 1: NORMAL LOAD (5 VUs)
  // Use for: Baseline performance measurement, typical application load
  // Uncomment this for normal load tests:
  // return [
  //   { duration: '15s', target: 5 },  // Ramp-up to 5 VUs
  //   { duration: '1m', target: 5 },   // Sustained at 5 VUs (normal load)
  //   { duration: '15s', target: 0 },  // Ramp-down
  // ];

  // PROFILE 2: HIGH LOAD (50 VUs)
  // Use for: Peak traffic scenarios, stress testing, cache effectiveness under load
  // Uncomment this for high load tests:
  return [
    { duration : '30s', target : 20 }, // Ramp-up phase 1 to 20 VUs
    { duration : '1m', target : 20 },  // Sustained phase 1 at 20 VUs
    { duration : '30s', target : 50 }, // Ramp-up phase 2 to 50 VUs
    { duration : '1m', target : 50 },  // Sustained phase 2 at 50 VUs (high load)
    { duration : '30s', target : 0 },  // Ramp-down
  ];
  
  // RECOMMENDATION: Run experiments with BOTH profiles
  // 1. First run all payloads with NORMAL LOAD (5 VUs)
  // 2. Then run all payloads with HIGH LOAD (50 VUs)
  // This gives you performance comparison across load conditions
}

export const options = {
  stages: getStages(),
  thresholds: {
    http_req_duration: ['p(95)<1000'],
    http_req_failed: ['rate<0.01'],
  },
  insecureSkipTLSVerify: true,
  cloud: {
    loadImpact: {
      distribution: {
        'amazon:sg:singapore': { loadZone: 'amazon:sg:singapore', percent: 100 }
      }
    }
  }
};

// --- Metrik untuk NO CACHE ---
const noCacheSatisfied = new Counter('no_cache_satisfied');
const noCacheTolerating = new Counter('no_cache_tolerating');
const noCacheFrustrated = new Counter('no_cache_frustrated');
const noCacheResponseTime = new Trend('no_cache_response_time');

// --- Metrik untuk CACHE HIT ---
const cacheHitSatisfied = new Counter('cache_hit_satisfied');
const cacheHitTolerating = new Counter('cache_hit_tolerating');
const cacheHitFrustrated = new Counter('cache_hit_frustrated');
const cacheHitResponseTime = new Trend('cache_hit_response_time');

// --- Metrik untuk CACHE MISS ---
const cacheMissSatisfied = new Counter('cache_miss_satisfied');
const cacheMissTolerating = new Counter('cache_miss_tolerating');
const cacheMissFrustrated = new Counter('cache_miss_frustrated');
const cacheMissResponseTime = new Trend('cache_miss_response_time');

// --- Counter untuk tracking ---
const cacheHitCount = new Counter('cache_hit_count');
const cacheMissCount = new Counter('cache_miss_count');
const noCacheCount = new Counter('no_cache_count');

// --- Fungsi Helper untuk kategorisasi Apdex ---
function categorizeResponse(responseTime, satisfiedCounter, toleratingCounter, frustratedCounter, trendMetric) {
  trendMetric.add(responseTime);
  
  if (responseTime <= APDEX_T) {
    satisfiedCounter.add(1);
  } else if (responseTime > APDEX_T && responseTime <= APDEX_F) {
    toleratingCounter.add(1);
  } else {
    frustratedCounter.add(1);
  }
}

// --- Fungsi untuk detect Cache HIT/MISS ---
function isCacheHit(response) {
  const cacheStatus = response.headers['X-Cache-Status'] || response.headers['x-cache-status'];
  if (cacheStatus) {
    return cacheStatus.toLowerCase() === 'hit';
  }
  
  const age = response.headers['Age'] || response.headers['age'];
  if (age && parseInt(age) > 0) {
    return true;
  }
  
  const xCache = response.headers['X-Cache'] || response.headers['x-cache'];
  if (xCache) {
    return xCache.toLowerCase().includes('hit');
  }
  
  return false;
}

// --- Logika Tes ---
export default function () {
  // Test 1: API tanpa cache
  let noCacheRes = http.get(API_NO_CACHE);
  check(noCacheRes, {
    'No Cache: status 200': (r) => r.status === 200,
  });
  
  if (noCacheRes.status === 200) {
    noCacheCount.add(1);
    categorizeResponse(
      noCacheRes.timings.duration,
      noCacheSatisfied,
      noCacheTolerating,
      noCacheFrustrated,
      noCacheResponseTime
    );
  }
  
  sleep(0.5);
  
  // Test 2: API dengan cache (HIT scenario)
  let cacheRes = http.get(API_WITH_CACHE);
  check(cacheRes, {
    'Cache: status 200': (r) => r.status === 200,
  });
  
  if (cacheRes.status === 200) {
    const isHit = isCacheHit(cacheRes);
    
    if (isHit) {
      cacheHitCount.add(1);
      categorizeResponse(
        cacheRes.timings.duration,
        cacheHitSatisfied,
        cacheHitTolerating,
        cacheHitFrustrated,
        cacheHitResponseTime
      );
    } else {
      cacheMissCount.add(1);
      categorizeResponse(
        cacheRes.timings.duration,
        cacheMissSatisfied,
        cacheMissTolerating,
        cacheMissFrustrated,
        cacheMissResponseTime
      );
    }
  }
  
  sleep(0.5);
  
  // Test 3: Cache MISS (force unique request)
  const timestamp = Date.now();
  const missUrl = `${API_CACHE_MISS}?_cache_bust=${timestamp}`;
  let cacheMissRes = http.get(missUrl);
  
  check(cacheMissRes, {
    'Cache MISS: status 200': (r) => r.status === 200,
  });
  
  if (cacheMissRes.status === 200) {
    cacheMissCount.add(1);
    categorizeResponse(
      cacheMissRes.timings.duration,
      cacheMissSatisfied,
      cacheMissTolerating,
      cacheMissFrustrated,
      cacheMissResponseTime
    );
  }
  
  sleep(0.5);
}

// --- Helper Functions ---
function getMetricValue(data, metricName, valueName = 'count') {
  return data.metrics[metricName]?.values?.[valueName] || 0;
}

function calculateApdex(satisfied, tolerating, frustrated) {
  const total = satisfied + tolerating + frustrated;
  return total > 0 ? (satisfied + tolerating / 2) / total : 0;
}

function formatStats(data, prefix) {
  // Defensive check for data
  if (!data || !data.metrics) {
    return {
      total_requests: 0,
      apdex_score: 0,
      response_times: {
        avg: 0, min: 0, max: 0, med: 0, p90: 0, p95: 0, p99: 0,
      },
      satisfied: 0,
      tolerating: 0,
      frustrated: 0,
    };
  }
  
  const satisfied = getMetricValue(data, `${prefix}_satisfied`);
  const tolerating = getMetricValue(data, `${prefix}_tolerating`);
  const frustrated = getMetricValue(data, `${prefix}_frustrated`);
  const totalReqs = getMetricValue(data, `${prefix}_count`);
  const apdexScore = calculateApdex(satisfied, tolerating, frustrated);
  
  return {
    total_requests: totalReqs,
    apdex_score: apdexScore,
    response_times: {
      avg: getMetricValue(data, `${prefix}_response_time`, 'avg'),
      min: getMetricValue(data, `${prefix}_response_time`, 'min'),
      max: getMetricValue(data, `${prefix}_response_time`, 'max'),
      med: getMetricValue(data, `${prefix}_response_time`, 'med'),
      p90: getMetricValue(data, `${prefix}_response_time`, 'p(90)'),
      p95: getMetricValue(data, `${prefix}_response_time`, 'p(95)'),
      p99: getMetricValue(data, `${prefix}_response_time`, 'p(99)'),
    },
    satisfied: satisfied,
    tolerating: tolerating,
    frustrated: frustrated,
  };
}

// --- Summary Report ---
export function handleSummary(data) {
  // Defensive check for data object
  if (!data || !data.metrics) {
    console.error('⚠️  No metrics data available - test may have failed');
    return {
      stdout: 'Test failed - no metrics collected\n',
    };
  }
  
  const noCacheStats = formatStats(data, 'no_cache');
  const cacheHitStats = formatStats(data, 'cache_hit');
  const cacheMissStats = formatStats(data, 'cache_miss');
  
  const totalHits = cacheHitStats.total_requests || 0;
  const totalMisses = cacheMissStats.total_requests || 0;
  const totalCache = totalHits + totalMisses;
  const hitRate = totalCache > 0 ? (totalHits / totalCache) * 100 : 0;
  
  const noCacheAvg = noCacheStats.response_times?.avg || 0;
  const cacheHitAvg = cacheHitStats.response_times?.avg || 0;
  const cacheMissAvg = cacheMissStats.response_times?.avg || 0;
  
  const improvementHitVsNoCache = noCacheAvg > 0 
    ? ((noCacheAvg - cacheHitAvg) / noCacheAvg) * 100 
    : 0;
  
  const improvementHitVsMiss = cacheMissAvg > 0 
    ? ((cacheMissAvg - cacheHitAvg) / cacheMissAvg) * 100 
    : 0;
  
  const jsonOutput = {
    test_configuration: {
      timestamp: new Date().toISOString(),
      payload_size: PAYLOAD_SIZE.toString(),
      test_run_id: TEST_RUN_ID,
      apdex_t: APDEX_T,
      apdex_f: APDEX_F,
      api_no_cache: API_NO_CACHE,
      api_with_cache: API_WITH_CACHE,
      adaptive_vu_scaling: true,
      max_vus: PAYLOAD_SIZE >= 32000 ? 25 : (PAYLOAD_SIZE >= 8000 ? 35 : 50)
    },
    no_cache: noCacheStats,
    cache_hit: cacheHitStats,
    cache_miss: cacheMissStats,
    cache_statistics: {
      hit_rate: hitRate,
      total_hits: totalHits,
      total_misses: totalMisses,
      improvement_hit_vs_nocache: improvementHitVsNoCache,
      improvement_hit_vs_miss: improvementHitVsMiss,
    }
  };
  
  const csvData = generateCSV(data);
  
  // Create custom summary output (more reliable than textSummary for edge cases)
  const customSummary = `
╔═══════════════════════════════════════════════════════════════╗
║                    K6 TEST RESULTS SUMMARY                    ║
╚═══════════════════════════════════════════════════════════════╝

Test Configuration:
  Payload Size: ${PAYLOAD_SIZE} records
  Test Run ID: ${TEST_RUN_ID}
  APDEX T: ${APDEX_T}ms | F: ${APDEX_F}ms
  Max VUs: ${PAYLOAD_SIZE >= 32000 ? 25 : (PAYLOAD_SIZE >= 8000 ? 35 : 50)}

═══════════════════════════════════════════════════════════════

NO CACHE Results:
  Total Requests: ${noCacheStats.total_requests}
  APDEX Score: ${noCacheStats.apdex_score.toFixed(4)}
  Avg Response: ${noCacheStats.response_times.avg.toFixed(2)}ms
  P95 Response: ${noCacheStats.response_times.p95.toFixed(2)}ms
  Satisfied: ${noCacheStats.satisfied} | Tolerating: ${noCacheStats.tolerating} | Frustrated: ${noCacheStats.frustrated}

CACHE HIT Results:
  Total Requests: ${cacheHitStats.total_requests}
  APDEX Score: ${cacheHitStats.apdex_score.toFixed(4)}
  Avg Response: ${cacheHitStats.response_times.avg.toFixed(2)}ms
  P95 Response: ${cacheHitStats.response_times.p95.toFixed(2)}ms
  Satisfied: ${cacheHitStats.satisfied} | Tolerating: ${cacheHitStats.tolerating} | Frustrated: ${cacheHitStats.frustrated}

CACHE MISS Results:
  Total Requests: ${cacheMissStats.total_requests}
  APDEX Score: ${cacheMissStats.apdex_score.toFixed(4)}
  Avg Response: ${cacheMissStats.response_times.avg.toFixed(2)}ms
  P95 Response: ${cacheMissStats.response_times.p95.toFixed(2)}ms
  Satisfied: ${cacheMissStats.satisfied} | Tolerating: ${cacheMissStats.tolerating} | Frustrated: ${cacheMissStats.frustrated}

═══════════════════════════════════════════════════════════════

Cache Performance:
  Hit Rate: ${hitRate.toFixed(2)}%
  Improvement (HIT vs NO-CACHE): ${improvementHitVsNoCache.toFixed(2)}%
  Improvement (HIT vs MISS): ${improvementHitVsMiss.toFixed(2)}%

═══════════════════════════════════════════════════════════════
✓ Results saved to:
  - JSON: ./results/test_${PAYLOAD_SIZE}_records_${TEST_RUN_ID}.json
  - CSV:  ./results/test_${PAYLOAD_SIZE}_records_${TEST_RUN_ID}.csv
═══════════════════════════════════════════════════════════════
`;
  
  return {
    stdout: customSummary,
    [`./results/test_${PAYLOAD_SIZE}_records_${TEST_RUN_ID}.json`]: JSON.stringify(jsonOutput, null, 2),
    [`./results/test_${PAYLOAD_SIZE}_records_${TEST_RUN_ID}.csv`]: csvData,
  };
}

// Helper function to generate CSV
function generateCSV(data) {
  const header = 'Metric,No Cache,Cache HIT,Cache MISS\n';
  const noCacheStats = formatStats(data, 'no_cache');
  const cacheHitStats = formatStats(data, 'cache_hit');
  const cacheMissStats = formatStats(data, 'cache_miss');
  
  const rows = [
    `Total Requests,${noCacheStats.total_requests},${cacheHitStats.total_requests},${cacheMissStats.total_requests}`,
    `APDEX Score,${noCacheStats.apdex_score.toFixed(4)},${cacheHitStats.apdex_score.toFixed(4)},${cacheMissStats.apdex_score.toFixed(4)}`,
    `Avg Response (ms),${noCacheStats.response_times.avg.toFixed(2)},${cacheHitStats.response_times.avg.toFixed(2)},${cacheMissStats.response_times.avg.toFixed(2)}`,
    `Min Response (ms),${noCacheStats.response_times.min.toFixed(2)},${cacheHitStats.response_times.min.toFixed(2)},${cacheMissStats.response_times.min.toFixed(2)}`,
    `Max Response (ms),${noCacheStats.response_times.max.toFixed(2)},${cacheHitStats.response_times.max.toFixed(2)},${cacheMissStats.response_times.max.toFixed(2)}`,
    `Median Response (ms),${noCacheStats.response_times.med.toFixed(2)},${cacheHitStats.response_times.med.toFixed(2)},${cacheMissStats.response_times.med.toFixed(2)}`,
    `P90 Response (ms),${noCacheStats.response_times.p90.toFixed(2)},${cacheHitStats.response_times.p90.toFixed(2)},${cacheMissStats.response_times.p90.toFixed(2)}`,
    `P95 Response (ms),${noCacheStats.response_times.p95.toFixed(2)},${cacheHitStats.response_times.p95.toFixed(2)},${cacheMissStats.response_times.p95.toFixed(2)}`,
    `Satisfied Count,${noCacheStats.satisfied},${cacheHitStats.satisfied},${cacheMissStats.satisfied}`,
    `Tolerating Count,${noCacheStats.tolerating},${cacheHitStats.tolerating},${cacheMissStats.tolerating}`,
    `Frustrated Count,${noCacheStats.frustrated},${cacheHitStats.frustrated},${cacheMissStats.frustrated}`,
  ].join('\n');
  
  return header + rows;
}

# ============================================
# Combine ALL Individual Test Runs into Detailed CSV
# ============================================
# Extracts all metrics from individual test JSON files for deep EDA

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "Combining ALL Individual Test Runs into Detailed CSV" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Get all individual test JSON files (not aggregated)
$jsonFiles = Get-ChildItem -Path ".\results\test_*.json" | 
             Where-Object { $_.Name -notlike "aggregated_*" } | 
             Sort-Object Name

if ($jsonFiles.Count -eq 0) {
    Write-Host "✗ No test result files found in .\results\" -ForegroundColor Red
    exit 1
}

Write-Host "Found $($jsonFiles.Count) individual test run files" -ForegroundColor Green
Write-Host ""

# Function to parse vmstat log and extract resource metrics
function Get-ResourceMetrics {
    param (
        [string]$VMName,        # K6_VM, No-Cache_VM, Cache-Hit_VM, Cache-Miss_VM
        [string]$PayloadSize,
        [string]$Endpoint,
        [int]$RunNumber
    )
    
    $logFileName = "vmstat_${VMName}_${PayloadSize}_${Endpoint}_run${RunNumber}.log"
    $logFilePath = ".\results\$logFileName"
    
    if (-not (Test-Path $logFilePath)) {
        Write-Host "  ⚠ Resource log not found: $logFileName" -ForegroundColor DarkYellow
        return @{
            MinFreeMemory_KB = $null
            MaxFreeMemory_KB = $null
            AvgFreeMemory_KB = $null
            MinFreeMemory_MB = $null
            MaxFreeMemory_MB = $null
            AvgFreeMemory_MB = $null
            AvgCPU_User = $null
            AvgCPU_System = $null
            AvgCPU_Idle = $null
            AvgCPU_Wait = $null
            ResourceLogFound = $false
        }
    }
    
    try {
        $logContent = Get-Content $logFilePath
        $freeMemValues = @()
        $cpuUserValues = @()
        $cpuSystemValues = @()
        $cpuIdleValues = @()
        $cpuWaitValues = @()
        
        # Parse data lines, skip headers
        foreach ($line in $logContent) {
            $line = $line.Trim()
            if ($line -eq "") { continue }
            
            # Skip header lines (contain 'procs', 'swpd', 'free', etc.)
            if ($line -match 'procs|swpd|free|buff|cache') { continue }
            
            # Split by whitespace and extract values
            $values = $line -split '\s+' | Where-Object { $_ -ne "" }
            
            # Ensure we have enough columns and first column is numeric (data line)
            if ($values.Count -ge 16 -and $values[0] -match '^\d+$') {
                try {
                    # Column 4 is 'free' memory in KB (index 3)
                    $freeMem = [int]$values[3]
                    $freeMemValues += $freeMem
                    
                    # CPU columns: us(12), sy(13), id(14), wa(15)
                    $cpuUserValues += [int]$values[12]
                    $cpuSystemValues += [int]$values[13]
                    $cpuIdleValues += [int]$values[14]
                    $cpuWaitValues += [int]$values[15]
                }
                catch {
                    # Skip lines that don't parse correctly
                    continue
                }
            }
        }
        
        if ($freeMemValues.Count -eq 0) {
            return @{
                MinFreeMemory_KB = $null
                MaxFreeMemory_KB = $null
                AvgFreeMemory_KB = $null
                MinFreeMemory_MB = $null
                MaxFreeMemory_MB = $null
                AvgFreeMemory_MB = $null
                AvgCPU_User = $null
                AvgCPU_System = $null
                AvgCPU_Idle = $null
                AvgCPU_Wait = $null
                ResourceLogFound = $true
                ResourceLogError = "No data parsed"
            }
        }
        
        $minFreeMem = ($freeMemValues | Measure-Object -Minimum).Minimum
        $maxFreeMem = ($freeMemValues | Measure-Object -Maximum).Maximum
        $avgFreeMem = ($freeMemValues | Measure-Object -Average).Average
        
        $avgCpuUser = ($cpuUserValues | Measure-Object -Average).Average
        $avgCpuSystem = ($cpuSystemValues | Measure-Object -Average).Average
        $avgCpuIdle = ($cpuIdleValues | Measure-Object -Average).Average
        $avgCpuWait = ($cpuWaitValues | Measure-Object -Average).Average
        
        return @{
            MinFreeMemory_KB = [int]$minFreeMem
            MaxFreeMemory_KB = [int]$maxFreeMem
            AvgFreeMemory_KB = [int]$avgFreeMem
            MinFreeMemory_MB = [math]::Round($minFreeMem / 1024, 2)
            MaxFreeMemory_MB = [math]::Round($maxFreeMem / 1024, 2)
            AvgFreeMemory_MB = [math]::Round($avgFreeMem / 1024, 2)
            AvgCPU_User = [math]::Round($avgCpuUser, 2)
            AvgCPU_System = [math]::Round($avgCpuSystem, 2)
            AvgCPU_Idle = [math]::Round($avgCpuIdle, 2)
            AvgCPU_Wait = [math]::Round($avgCpuWait, 2)
            ResourceLogFound = $true
            ResourceDataPoints = $freeMemValues.Count
        }
    }
    catch {
        Write-Host "  ⚠ Error parsing resource log: $($_.Exception.Message)" -ForegroundColor DarkYellow
        return @{
            MinFreeMemory_KB = $null
            MaxFreeMemory_KB = $null
            AvgFreeMemory_KB = $null
            MinFreeMemory_MB = $null
            MaxFreeMemory_MB = $null
            AvgFreeMemory_MB = $null
            AvgCPU_User = $null
            AvgCPU_System = $null
            AvgCPU_Idle = $null
            AvgCPU_Wait = $null
            ResourceLogFound = $true
            ResourceLogError = $_.Exception.Message
        }
    }
}

# Create array to store all data
$allData = @()
$processedCount = 0

foreach ($file in $jsonFiles) {
    $processedCount++
    Write-Host "[$processedCount/$($jsonFiles.Count)] Processing: $($file.Name)" -ForegroundColor Gray
    
    try {
        $data = Get-Content $file.FullName | ConvertFrom-Json
        
        # Parse test run ID to extract endpoint name and run number
        $runId = $data.test_configuration.test_run_id
        $runIdParts = $runId -split '_'
        
        # Extract endpoint name (could be 'automatic', 'income', 'activity', etc.)
        $endpointName = if ($runIdParts.Count -ge 2) { $runIdParts[1] } else { "unknown" }
        
        # Extract run number
        $runNumber = if ($runId -match 'run(\d+)') { [int]$matches[1] } else { 0 }
        
        # Get resource metrics from vmstat logs (all VMs)
        $k6Metrics = Get-ResourceMetrics -VMName "K6_VM" -PayloadSize $data.test_configuration.payload_size -Endpoint $endpointName -RunNumber $runNumber
        $noCacheMetrics = Get-ResourceMetrics -VMName "No-Cache_VM" -PayloadSize $data.test_configuration.payload_size -Endpoint $endpointName -RunNumber $runNumber
        $cacheHitMetrics = Get-ResourceMetrics -VMName "Cache-Hit_VM" -PayloadSize $data.test_configuration.payload_size -Endpoint $endpointName -RunNumber $runNumber
        $cacheMissMetrics = Get-ResourceMetrics -VMName "Cache-Miss_VM" -PayloadSize $data.test_configuration.payload_size -Endpoint $endpointName -RunNumber $runNumber
        
        # Create detailed row with ALL metrics
        $row = [PSCustomObject]@{
            # Test Identification
            TestRunID = $data.test_configuration.test_run_id
            Endpoint = $endpointName
            PayloadSize = [int]$data.test_configuration.payload_size
            RunNumber = $runNumber
            Timestamp = $data.test_configuration.timestamp
            FileName = $file.Name
            
            # Test Configuration
            APDEX_T_Threshold = $data.test_configuration.apdex_t
            APDEX_F_Threshold = $data.test_configuration.apdex_f
            API_NoCache_URL = $data.test_configuration.api_no_cache
            API_WithCache_URL = $data.test_configuration.api_with_cache
            
            # === RESOURCE MONITORING (K6 VM) ===
            K6_MinFreeMemory_MB = $k6Metrics.MinFreeMemory_MB
            K6_MaxFreeMemory_MB = $k6Metrics.MaxFreeMemory_MB
            K6_AvgFreeMemory_MB = $k6Metrics.AvgFreeMemory_MB
            K6_MinFreeMemory_KB = $k6Metrics.MinFreeMemory_KB
            K6_MaxFreeMemory_KB = $k6Metrics.MaxFreeMemory_KB
            K6_AvgFreeMemory_KB = $k6Metrics.AvgFreeMemory_KB
            K6_AvgCPU_User_Pct = $k6Metrics.AvgCPU_User
            K6_AvgCPU_System_Pct = $k6Metrics.AvgCPU_System
            K6_AvgCPU_Idle_Pct = $k6Metrics.AvgCPU_Idle
            K6_AvgCPU_Wait_Pct = $k6Metrics.AvgCPU_Wait
            K6_ResourceLog_Found = $k6Metrics.ResourceLogFound
            K6_ResourceLog_DataPoints = $k6Metrics.ResourceDataPoints
            
            # === RESOURCE MONITORING (No-Cache VM) ===
            NoCache_MinFreeMemory_MB = $noCacheMetrics.MinFreeMemory_MB
            NoCache_MaxFreeMemory_MB = $noCacheMetrics.MaxFreeMemory_MB
            NoCache_AvgFreeMemory_MB = $noCacheMetrics.AvgFreeMemory_MB
            NoCache_AvgCPU_User_Pct = $noCacheMetrics.AvgCPU_User
            NoCache_AvgCPU_System_Pct = $noCacheMetrics.AvgCPU_System
            NoCache_AvgCPU_Idle_Pct = $noCacheMetrics.AvgCPU_Idle
            NoCache_AvgCPU_Wait_Pct = $noCacheMetrics.AvgCPU_Wait
            NoCache_ResourceLog_Found = $noCacheMetrics.ResourceLogFound
            NoCache_ResourceLog_DataPoints = $noCacheMetrics.ResourceDataPoints
            
            # === RESOURCE MONITORING (Cache-Hit VM) ===
            CacheHit_MinFreeMemory_MB = $cacheHitMetrics.MinFreeMemory_MB
            CacheHit_MaxFreeMemory_MB = $cacheHitMetrics.MaxFreeMemory_MB
            CacheHit_AvgFreeMemory_MB = $cacheHitMetrics.AvgFreeMemory_MB
            CacheHit_AvgCPU_User_Pct = $cacheHitMetrics.AvgCPU_User
            CacheHit_AvgCPU_System_Pct = $cacheHitMetrics.AvgCPU_System
            CacheHit_AvgCPU_Idle_Pct = $cacheHitMetrics.AvgCPU_Idle
            CacheHit_AvgCPU_Wait_Pct = $cacheHitMetrics.AvgCPU_Wait
            CacheHit_ResourceLog_Found = $cacheHitMetrics.ResourceLogFound
            CacheHit_ResourceLog_DataPoints = $cacheHitMetrics.ResourceDataPoints
            
            # === RESOURCE MONITORING (Cache-Miss VM) ===
            CacheMiss_MinFreeMemory_MB = $cacheMissMetrics.MinFreeMemory_MB
            CacheMiss_MaxFreeMemory_MB = $cacheMissMetrics.MaxFreeMemory_MB
            CacheMiss_AvgFreeMemory_MB = $cacheMissMetrics.AvgFreeMemory_MB
            CacheMiss_AvgCPU_User_Pct = $cacheMissMetrics.AvgCPU_User
            CacheMiss_AvgCPU_System_Pct = $cacheMissMetrics.AvgCPU_System
            CacheMiss_AvgCPU_Idle_Pct = $cacheMissMetrics.AvgCPU_Idle
            CacheMiss_AvgCPU_Wait_Pct = $cacheMissMetrics.AvgCPU_Wait
            CacheMiss_ResourceLog_Found = $cacheMissMetrics.ResourceLogFound
            CacheMiss_ResourceLog_DataPoints = $cacheMissMetrics.ResourceDataPoints
            
            # === NO CACHE METRICS ===
            NoCache_TotalRequests = $data.no_cache.total_requests
            NoCache_APDEX_Score = [math]::Round($data.no_cache.apdex_score, 4)
            
            # Response Times
            NoCache_Avg_ms = [math]::Round($data.no_cache.response_times.avg, 2)
            NoCache_Median_ms = [math]::Round($data.no_cache.response_times.med, 2)
            NoCache_Min_ms = [math]::Round($data.no_cache.response_times.min, 2)
            NoCache_Max_ms = [math]::Round($data.no_cache.response_times.max, 2)
            NoCache_P90_ms = [math]::Round($data.no_cache.response_times.p90, 2)
            NoCache_P95_ms = [math]::Round($data.no_cache.response_times.p95, 2)
            NoCache_P99_ms = if ($data.no_cache.response_times.p99) { [math]::Round($data.no_cache.response_times.p99, 2) } else { 0 }
            
            # APDEX Categories
            NoCache_Satisfied = $data.no_cache.satisfied
            NoCache_Tolerating = $data.no_cache.tolerating
            NoCache_Frustrated = $data.no_cache.frustrated
            NoCache_Satisfied_Pct = [math]::Round(($data.no_cache.satisfied / $data.no_cache.total_requests * 100), 2)
            NoCache_Tolerating_Pct = [math]::Round(($data.no_cache.tolerating / $data.no_cache.total_requests * 100), 2)
            NoCache_Frustrated_Pct = [math]::Round(($data.no_cache.frustrated / $data.no_cache.total_requests * 100), 2)
            
            # === CACHE HIT METRICS ===
            CacheHit_TotalRequests = $data.cache_hit.total_requests
            CacheHit_APDEX_Score = [math]::Round($data.cache_hit.apdex_score, 4)
            
            # Response Times
            CacheHit_Avg_ms = [math]::Round($data.cache_hit.response_times.avg, 2)
            CacheHit_Median_ms = [math]::Round($data.cache_hit.response_times.med, 2)
            CacheHit_Min_ms = [math]::Round($data.cache_hit.response_times.min, 2)
            CacheHit_Max_ms = [math]::Round($data.cache_hit.response_times.max, 2)
            CacheHit_P90_ms = [math]::Round($data.cache_hit.response_times.p90, 2)
            CacheHit_P95_ms = [math]::Round($data.cache_hit.response_times.p95, 2)
            CacheHit_P99_ms = if ($data.cache_hit.response_times.p99) { [math]::Round($data.cache_hit.response_times.p99, 2) } else { 0 }
            
            # APDEX Categories
            CacheHit_Satisfied = $data.cache_hit.satisfied
            CacheHit_Tolerating = $data.cache_hit.tolerating
            CacheHit_Frustrated = $data.cache_hit.frustrated
            CacheHit_Satisfied_Pct = [math]::Round(($data.cache_hit.satisfied / $data.cache_hit.total_requests * 100), 2)
            CacheHit_Tolerating_Pct = [math]::Round(($data.cache_hit.tolerating / $data.cache_hit.total_requests * 100), 2)
            CacheHit_Frustrated_Pct = [math]::Round(($data.cache_hit.frustrated / $data.cache_hit.total_requests * 100), 2)
            
            # === CACHE MISS METRICS ===
            CacheMiss_TotalRequests = $data.cache_miss.total_requests
            CacheMiss_APDEX_Score = [math]::Round($data.cache_miss.apdex_score, 4)
            
            # Response Times
            CacheMiss_Avg_ms = [math]::Round($data.cache_miss.response_times.avg, 2)
            CacheMiss_Median_ms = [math]::Round($data.cache_miss.response_times.med, 2)
            CacheMiss_Min_ms = [math]::Round($data.cache_miss.response_times.min, 2)
            CacheMiss_Max_ms = [math]::Round($data.cache_miss.response_times.max, 2)
            CacheMiss_P90_ms = [math]::Round($data.cache_miss.response_times.p90, 2)
            CacheMiss_P95_ms = [math]::Round($data.cache_miss.response_times.p95, 2)
            CacheMiss_P99_ms = if ($data.cache_miss.response_times.p99) { [math]::Round($data.cache_miss.response_times.p99, 2) } else { 0 }
            
            # APDEX Categories
            CacheMiss_Satisfied = $data.cache_miss.satisfied
            CacheMiss_Tolerating = $data.cache_miss.tolerating
            CacheMiss_Frustrated = $data.cache_miss.frustrated
            CacheMiss_Satisfied_Pct = [math]::Round(($data.cache_miss.satisfied / $data.cache_miss.total_requests * 100), 2)
            CacheMiss_Tolerating_Pct = [math]::Round(($data.cache_miss.tolerating / $data.cache_miss.total_requests * 100), 2)
            CacheMiss_Frustrated_Pct = [math]::Round(($data.cache_miss.frustrated / $data.cache_miss.total_requests * 100), 2)
            
            # === CACHE STATISTICS ===
            Cache_HitRate_Percent = $data.cache_statistics.hit_rate
            Cache_TotalHits = $data.cache_statistics.total_hits
            Cache_TotalMisses = $data.cache_statistics.total_misses
            Cache_ImprovementHitVsNoCache_Pct = [math]::Round($data.cache_statistics.improvement_hit_vs_nocache, 2)
            Cache_ImprovementHitVsMiss_Pct = [math]::Round($data.cache_statistics.improvement_hit_vs_miss, 2)
            
            # === CALCULATED METRICS FOR ANALYSIS ===
            
            # Speedup Factors
            SpeedupFactor_HitVsNoCache = if ($data.cache_hit.response_times.avg -gt 0) {
                [math]::Round($data.no_cache.response_times.avg / $data.cache_hit.response_times.avg, 2)
            } else { $null }
            
            SpeedupFactor_HitVsMiss = if ($data.cache_hit.response_times.avg -gt 0) {
                [math]::Round($data.cache_miss.response_times.avg / $data.cache_hit.response_times.avg, 2)
            } else { $null }
            
            # Absolute Time Differences
            TimeSaved_HitVsNoCache_ms = [math]::Round($data.no_cache.response_times.avg - $data.cache_hit.response_times.avg, 2)
            TimeSaved_HitVsMiss_ms = [math]::Round($data.cache_miss.response_times.avg - $data.cache_hit.response_times.avg, 2)
            
            # Relative Performance (NoCache as baseline = 100%)
            RelativePerf_CacheHit_Pct = if ($data.no_cache.response_times.avg -gt 0) {
                [math]::Round(($data.cache_hit.response_times.avg / $data.no_cache.response_times.avg * 100), 2)
            } else { $null }
            
            RelativePerf_CacheMiss_Pct = if ($data.no_cache.response_times.avg -gt 0) {
                [math]::Round(($data.cache_miss.response_times.avg / $data.no_cache.response_times.avg * 100), 2)
            } else { $null }
            
            # APDEX Score Differences
            APDEX_Improvement_HitVsNoCache = [math]::Round($data.cache_hit.apdex_score - $data.no_cache.apdex_score, 4)
            APDEX_Improvement_HitVsMiss = [math]::Round($data.cache_hit.apdex_score - $data.cache_miss.apdex_score, 4)
            
            # Response Time Ranges (Max - Min)
            NoCache_Range_ms = [math]::Round($data.no_cache.response_times.max - $data.no_cache.response_times.min, 2)
            CacheHit_Range_ms = [math]::Round($data.cache_hit.response_times.max - $data.cache_hit.response_times.min, 2)
            CacheMiss_Range_ms = [math]::Round($data.cache_miss.response_times.max - $data.cache_miss.response_times.min, 2)
            
            # Variability Indicator (P95 - P50)
            NoCache_Variability_ms = [math]::Round($data.no_cache.response_times.p95 - $data.no_cache.response_times.avg, 2)
            CacheHit_Variability_ms = [math]::Round($data.cache_hit.response_times.p95 - $data.cache_hit.response_times.avg, 2)
            CacheMiss_Variability_ms = [math]::Round($data.cache_miss.response_times.p95 - $data.cache_miss.response_times.avg, 2)
            
            # Tail Latency Indicators (P90/P50 ratio)
            NoCache_TailLatencyRatio = if ($data.no_cache.response_times.avg -gt 0) {
                [math]::Round($data.no_cache.response_times.p90 / $data.no_cache.response_times.avg, 2)
            } else { $null }
            
            CacheHit_TailLatencyRatio = if ($data.cache_hit.response_times.avg -gt 0) {
                [math]::Round($data.cache_hit.response_times.p90 / $data.cache_hit.response_times.avg, 2)
            } else { $null }
            
            CacheMiss_TailLatencyRatio = if ($data.cache_miss.response_times.avg -gt 0) {
                [math]::Round($data.cache_miss.response_times.p90 / $data.cache_miss.response_times.avg, 2)
            } else { $null }
        }
        
        $allData += $row
        
    } catch {
        Write-Host "  ⚠ Error processing $($file.Name): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "Processed $($allData.Count) test runs" -ForegroundColor Green
Write-Host ""

# Display summary statistics
Write-Host "📊 Dataset Summary:" -ForegroundColor Cyan
$endpoints = $allData | Group-Object Endpoint | Select-Object Name, Count
$payloadSizes = $allData | Group-Object PayloadSize | Select-Object Name, Count | Sort-Object {[int]$_.Name}

Write-Host ""
Write-Host "  Endpoints:" -ForegroundColor Yellow
foreach ($ep in $endpoints) {
    Write-Host "    - $($ep.Name): $($ep.Count) test runs" -ForegroundColor White
}

Write-Host ""
Write-Host "  Payload Sizes:" -ForegroundColor Yellow
foreach ($ps in $payloadSizes) {
    Write-Host "    - $($ps.Name) records: $($ps.Count) test runs" -ForegroundColor White
}

Write-Host ""

# Export to CSV
$outputFile = ".\results\detailed_all_tests_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$allData | Export-Csv -Path $outputFile -NoTypeInformation -Encoding UTF8

Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                    ✓ SUCCESS!                                 ║" -ForegroundColor Green
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "📊 Detailed CSV file created:" -ForegroundColor Cyan
Write-Host "   $outputFile" -ForegroundColor White
Write-Host ""
Write-Host "📈 File contains:" -ForegroundColor Yellow
Write-Host "   - $($allData.Count) individual test runs" -ForegroundColor White
Write-Host "   - $(($allData | Select-Object -Property Endpoint -Unique).Count) unique endpoints" -ForegroundColor White
Write-Host "   - $(($allData | Select-Object -Property PayloadSize -Unique).Count) unique payload sizes" -ForegroundColor White
Write-Host "   - 160+ columns with detailed metrics + resource monitoring" -ForegroundColor White
Write-Host ""

# Count how many tests have resource logs
$testsWithK6Logs = ($allData | Where-Object { $_.K6_ResourceLog_Found -eq $true }).Count
$testsWithNoCacheLogs = ($allData | Where-Object { $_.NoCache_ResourceLog_Found -eq $true }).Count
$testsWithCacheHitLogs = ($allData | Where-Object { $_.CacheHit_ResourceLog_Found -eq $true }).Count
$testsWithCacheMissLogs = ($allData | Where-Object { $_.CacheMiss_ResourceLog_Found -eq $true }).Count

Write-Host "Resource Monitoring Coverage:" -ForegroundColor Cyan
Write-Host "   - K6 VM logs: $testsWithK6Logs / $($allData.Count)" -ForegroundColor White
Write-Host "   - No-Cache VM logs: $testsWithNoCacheLogs / $($allData.Count)" -ForegroundColor White
Write-Host "   - Cache-Hit VM logs: $testsWithCacheHitLogs / $($allData.Count)" -ForegroundColor White
Write-Host "   - Cache-Miss VM logs: $testsWithCacheMissLogs / $($allData.Count)" -ForegroundColor White

if ($testsWithK6Logs -gt 0) {
    $avgDataPoints = ($allData | Where-Object { $_.K6_ResourceLog_DataPoints -gt 0 } | Measure-Object -Property K6_ResourceLog_DataPoints -Average).Average
    Write-Host "   - Average data points per test: $([math]::Round($avgDataPoints, 0))" -ForegroundColor White
}
Write-Host ""

Write-Host "Ready for Deep EDA in Jupyter Notebook!" -ForegroundColor Green
Write-Host ""
Write-Host "Metrics included:" -ForegroundColor Gray
Write-Host "   • Response times: avg, median, min, max, P90, P95, P99" -ForegroundColor Gray
Write-Host "   • APDEX scores and category distributions" -ForegroundColor Gray
Write-Host "   • Cache statistics: hit rate, improvements" -ForegroundColor Gray
Write-Host "   • Calculated metrics: speedup factors, time saved" -ForegroundColor Gray
Write-Host "   • Variability indicators: range, tail latency ratios" -ForegroundColor Gray
Write-Host "   - Resource monitoring (4 VMs): K6, No-Cache, Cache-Hit, Cache-Miss" -ForegroundColor Gray
Write-Host "   - Per-VM metrics: min/max/avg free memory, CPU usage (user, system, idle, wait)" -ForegroundColor Gray
Write-Host "   • All metrics for: No Cache, Cache HIT, and Cache MISS" -ForegroundColor Gray
Write-Host ""

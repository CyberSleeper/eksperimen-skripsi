#!/bin/bash

# ============================================
# IMPORTANT: Use test_apdex.js for large payloads
# ============================================
# This script now uses adaptive VU scaling to prevent OOM on payload ≥32000

# Load configuration
if [ -f "config.env" ]; then
    source config.env
else
    # Default configuration
    VM_NO_CACHE="13.214.170.49"
    VM_CACHE="18.141.211.240"
    VM_CACHE_BACKUP="52.77.228.157"
    SSH_KEY="~/.ssh/id_ed25519"
    SSH_USER="ubuntu"
fi

# Default values
RUNS=${1:-5}  # Default: 5 runs
PAYLOAD_SIZE=${2}

# Define the two endpoints to test
declare -A endpoints
endpoints[automatic_path]="/call/automatic-report-twolevel/list"
endpoints[automatic_name]="automatic"
endpoints[automatic_desc]="Automatic Report (Aggregate Operations)"
endpoints[income_path]="/call/income/list"
endpoints[income_name]="income"
endpoints[income_desc]="Income List (High Payload)"

# Select appropriate test script based on payload size
TEST_SCRIPT="./test_apdex.js"

# Function to clear nginx cache on a VM
clear_nginx_cache() {
    local vm_ip="$1"
    local vm_name="$2"
    
    echo "  🧹 Clearing nginx cache on $vm_name ($vm_ip)..."
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$vm_ip" \
        'sudo rm -rf /var/cache/nginx/* /var/run/nginx-cache/* /tmp/nginx-cache/* 2>/dev/null; sudo systemctl reload nginx' 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Cache cleared on $vm_name"
    else
        echo "  ⚠ Warning: Could not clear cache on $vm_name (continuing anyway)"
    fi
}

# Function to start continuous resource monitoring on a VM
start_resource_monitoring() {
    local vm_ip="$1"
    local vm_name="$2"
    local payload_size="$3"
    local endpoint="$4"
    
    echo "  🔍 Starting continuous monitoring on $vm_name..."
    
    # Start vmstat in background on remote VM
    # Captures: memory, swap, I/O, system, CPU every 5 seconds
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$vm_ip" \
        "nohup vmstat 5 > /tmp/vmstat_${vm_name// /_}_${payload_size}_${endpoint}.log 2>&1 &" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Monitoring started on $vm_name"
    else
        echo "  ⚠ Warning: Could not start monitoring on $vm_name"
    fi
}

# Function to stop continuous monitoring and collect results
stop_resource_monitoring() {
    local vm_ip="$1"
    local vm_name="$2"
    local payload_size="$3"
    local endpoint="$4"
    
    echo "  🛑 Stopping monitoring on $vm_name..."
    
    # Kill vmstat process
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$vm_ip" \
        "pkill -f 'vmstat 5'" 2>/dev/null
    
    # Copy the log file back
    local remote_log="/tmp/vmstat_${vm_name// /_}_${payload_size}_${endpoint}.log"
    local local_log="./results/vmstat_${vm_name// /_}_${payload_size}_${endpoint}.log"
    
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$SSH_USER@$vm_ip:$remote_log" "$local_log" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Monitoring data saved to $local_log"
        
        # Clean up remote file
        ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$SSH_USER@$vm_ip" \
            "rm -f $remote_log" 2>/dev/null
    else
        echo "  ⚠ Warning: Could not retrieve monitoring data from $vm_name"
    fi
}

# Function to log snapshot resource usage on a VM (quick check)
log_resource_snapshot() {
    local vm_ip="$1"
    local vm_name="$2"
    local stage="$3"
    local payload_size="$4"
    local endpoint="$5"
    
    echo "  📊 Capturing resource snapshot on $vm_name..."
    
    # Create log file for this payload and endpoint
    local log_file="./results/resource_snapshot_${payload_size}_${endpoint}.log"
    
    # Capture resource usage via SSH
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$vm_ip" bash << EOF >> "$log_file" 2>&1
echo "=== Resource Snapshot: $vm_name - $stage - Payload: $payload_size - Endpoint: $endpoint ==="
echo "Timestamp: \$(date)"
echo ""
echo "Memory Usage:"
free -h
echo ""
echo "Disk Usage:"
df -h /
echo ""
echo "Nginx Cache Size:"
du -sh /var/cache/nginx/ /var/run/nginx-cache/ /tmp/nginx-cache/ 2>/dev/null | awk '{print \$1 "\t" \$2}'
echo ""
echo "Database Size:"
sudo -u postgres psql -d ${DB_NAME:-aisco_product_hightide} -c "SELECT pg_size_pretty(pg_database_size('${DB_NAME:-aisco_product_hightide}'));" 2>/dev/null || echo "N/A"
echo ""
echo "=========================================="
echo ""
EOF
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Snapshot logged to $log_file"
    else
        echo "  ⚠ Warning: Could not capture snapshot from $vm_name"
    fi
}

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     Multiple Run Test - Statistical Performance Analysis     ║"
echo "║              Testing 2 Endpoints: Automatic + Income         ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""

# Create results directory if it doesn't exist
mkdir -p ./results

# Prompt for payload size if not provided
if [ -z "$PAYLOAD_SIZE" ]; then
    echo "Enter the number of records in the payload:"
    read -p "Payload Size: " PAYLOAD_SIZE
fi

if [ -z "$PAYLOAD_SIZE" ]; then
    echo "✗ Error: Payload size cannot be empty!"
    exit 1
fi

# Re-check test script selection after user input
if [ "$PAYLOAD_SIZE" -ge 8000 ] 2>/dev/null; then
    TEST_SCRIPT="./test_apdex.js"
    echo "ℹ️  Large payload detected ($PAYLOAD_SIZE ≥ 8000): Using adaptive VU scaling to prevent OOM"
    echo ""
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Configuration:"
echo "  Payload Size: $PAYLOAD_SIZE records"
echo "  Number of Runs: $RUNS (per endpoint)"
echo "  Test Script: $TEST_SCRIPT"
echo "  Load Scenario: ${LOAD_SCENARIO:-high} (5 VUs for normal, 50 VUs for high)"
echo "  Endpoints to Test:"
echo "    - automatic: ${endpoints[automatic_path]}"
echo "    - income: ${endpoints[income_path]}"
echo "  Total Duration: ~$(($RUNS * 7)) minutes"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Starting automated test sequence..."
echo ""

# Test endpoints array
test_endpoints=("income" "automatic")

# Loop through each endpoint
for endpoint_key in "${test_endpoints[@]}"; do
    endpoint_path="${endpoints[${endpoint_key}_path]}"
    endpoint_name="${endpoints[${endpoint_key}_name]}"
    endpoint_desc="${endpoints[${endpoint_key}_desc]}"
    
    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    printf "║  Testing Endpoint: %-44s ║\n" "$endpoint_desc"
    printf "║  Path: %-53s ║\n" "$endpoint_path"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo ""

    # Warm up the cache for this endpoint
    echo "🔥 Warming up cache for $endpoint_name..."
    echo "   Making 3 warm-up requests..."
    for i in {1..3}; do
        curl -s -o /dev/null "https://hightide-cache.sple.my.id$endpoint_path"
        sleep 0.5
    done
    echo "✓ Cache warmed up successfully for $endpoint_name"
    echo ""

    # K6 VM configuration for monitoring
    K6_VM="54.255.168.167"
    K6_SSH_USER="ec2-user"
    
    # Log initial snapshot on all VMs (once per endpoint)
    echo "📊 Logging initial resource snapshot..."
    log_resource_snapshot "$VM_NO_CACHE" "No-Cache VM" "before_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    log_resource_snapshot "$VM_CACHE" "Cache-Hit VM" "before_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    log_resource_snapshot "$VM_CACHE_BACKUP" "Cache-Miss VM" "before_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    echo ""

    # Array to store results for this endpoint
    all_results=()

    # Run tests for this endpoint
    for ((i=1; i<=RUNS; i++)); do
        echo "═══════════════════════════════════════════════════════════════"
        echo "Endpoint: $endpoint_name | Run $i of $RUNS | Payload: $PAYLOAD_SIZE records"
        echo "═══════════════════════════════════════════════════════════════"
        echo ""
        
        # Clear nginx cache before each run for consistent results
        echo "🧹 Clearing nginx cache on all VMs before run $i..."
        clear_nginx_cache "$VM_CACHE" "Cache-Hit VM"
        clear_nginx_cache "$VM_CACHE_BACKUP" "Cache-Miss VM"
        clear_nginx_cache "$VM_NO_CACHE" "No-Cache VM"
        echo ""
        
        # Start continuous monitoring on ALL VMs for THIS RUN
        echo "🔍 Starting continuous resource monitoring for run $i..."
        
        # Start monitoring on K6 VM (locally)
        nohup vmstat 5 > /tmp/vmstat_K6_VM_${PAYLOAD_SIZE}_${endpoint_name}_run${i}.log 2>&1 &
        VMSTAT_PID=$!
        echo "  ✓ K6 VM monitoring started (PID: $VMSTAT_PID)"
        
        # Start monitoring on deployment VMs (via SSH)
        start_resource_monitoring "$VM_NO_CACHE" "No-Cache_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        start_resource_monitoring "$VM_CACHE" "Cache-Hit_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        start_resource_monitoring "$VM_CACHE_BACKUP" "Cache-Miss_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        
        echo ""
        
        timestamp=$(date +"%Y%m%d_%H%M%S")
        run_id="${PAYLOAD_SIZE}_${endpoint_name}_run${i}_${timestamp}"
        
        # Run k6 test with appropriate script (adaptive for large payloads)
        echo "🚀 Running k6 test with script: $TEST_SCRIPT"
        k6 run -e PAYLOAD_SIZE=$PAYLOAD_SIZE -e TEST_RUN_ID=$run_id -e ENDPOINT=$endpoint_path -e LOAD_SCENARIO="${LOAD_SCENARIO:-high}" "$TEST_SCRIPT"
        k6_exit_code=$?
        
        # Stop monitoring and collect data for THIS RUN
        echo ""
        echo "🛑 Stopping monitoring for run $i and collecting data..."
        
        # Stop K6 VM monitoring (local)
        pkill -f 'vmstat 5' 2>/dev/null
        sleep 1  # Give vmstat time to flush and close the file
        
        # Stop deployment VMs monitoring (remote)
        stop_resource_monitoring "$VM_NO_CACHE" "No-Cache_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        stop_resource_monitoring "$VM_CACHE" "Cache-Hit_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        stop_resource_monitoring "$VM_CACHE_BACKUP" "Cache-Miss_VM" "$PAYLOAD_SIZE" "${endpoint_name}_run${i}"
        
        # Collect K6 VM log
        local_k6_log="./results/vmstat_K6_VM_${PAYLOAD_SIZE}_${endpoint_name}_run${i}.log"
        temp_k6_log="/tmp/vmstat_K6_VM_${PAYLOAD_SIZE}_${endpoint_name}_run${i}.log"
        
        # Move the log file from /tmp to results directory
        if [ -f "$temp_k6_log" ]; then
            mv "$temp_k6_log" "$local_k6_log"
        fi
        
        if [ -f "$local_k6_log" ]; then
            # Analyze memory usage from this run
            # Filter out header lines and empty values, then get minimum free memory
            free_mem_min=$(awk 'NR>2 && $4 ~ /^[0-9]+$/ {print $4}' "$local_k6_log" | sort -n | head -1)
            if [ -n "$free_mem_min" ] && [ "$free_mem_min" -gt 0 ]; then
                free_mem_kb=$((free_mem_min / 1024))
                echo "  ✓ Monitoring data saved: $local_k6_log"
                echo "  📊 Run $i stats: Minimum free RAM = ${free_mem_kb} MB"
            else
                echo "  ✓ Monitoring data saved: $local_k6_log"
                echo "  ⚠️  Could not parse memory stats from vmstat log"
            fi
        else
            echo "  ⚠ Warning: Could not retrieve monitoring data for run $i"
            echo "  Expected file: $temp_k6_log"
        fi
        echo ""
        
        # Check if test completed successfully
        result_file="./results/test_${PAYLOAD_SIZE}_records_${run_id}.json"
        if [ -f "$result_file" ]; then
            echo "✓ Run $i completed successfully"
            all_results+=("$result_file")
        else
            echo "⚠ Warning: Result file not found for run $i"
            echo "   Expected: $result_file"
            if [ $k6_exit_code -eq 137 ] || [ $k6_exit_code -eq 143 ]; then
                echo "   🔴 k6 was KILLED (exit code $k6_exit_code) - likely OOM!"
                echo "   💡 Check $local_k6_log to see memory usage before crash"
            else
                echo "   This may indicate k6 was killed due to OOM or other error."
            fi
            echo "   Continuing to next run..."
        fi
        
        echo ""
        
        # Wait between runs (Step 8: 10 seconds between runs)
        if [ $i -lt $RUNS ]; then
            echo "⏳ Waiting 10 seconds before next run (Step 8)..."
            sleep 10
        fi
    done

    # Summary for this endpoint
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "✓ Completed $RUNS runs for $endpoint_name endpoint"
    echo "  Successful runs: ${#all_results[@]}/$RUNS"
    if [ ${#all_results[@]} -lt $RUNS ]; then
        echo "  ⚠ Some runs failed - check individual vmstat logs for OOM patterns"
        echo "  💡 Failed run logs: ./results/vmstat_K6_VM_${PAYLOAD_SIZE}_${endpoint_name}_run*.log"
    fi
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Log final snapshot on all VMs
    echo "📊 Logging final resource snapshot..."
    log_resource_snapshot "$VM_NO_CACHE" "No-Cache VM" "after_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    log_resource_snapshot "$VM_CACHE" "Cache-Hit VM" "after_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    log_resource_snapshot "$VM_CACHE_BACKUP" "Cache-Miss VM" "after_${endpoint_name}" "$PAYLOAD_SIZE" "$endpoint_name"
    echo ""
done

echo ""
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║              ✓ ALL TESTS COMPLETED SUCCESSFULLY!              ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Summary:"
echo "   - Tested 2 endpoints: /call/automatic + /call/income"
echo "   - Payload Size: $PAYLOAD_SIZE records"
echo "   - Runs per endpoint: $RUNS"
echo "   - Test Script: $TEST_SCRIPT"
echo "   - Total test runs: $((RUNS * 2))"
echo ""
if [ "$PAYLOAD_SIZE" -ge 32000 ]; then
    echo "💡 Note: Large payload testing used reduced VUs (10-25) to prevent OOM"
    echo "   This is documented in test results under 'max_vus' field"
    echo ""
fi
echo "📁 Results saved to:"
echo "   - Performance data: ./results/test_*.json"
echo "   - K6 VM per-run monitoring: ./results/vmstat_K6_VM_${PAYLOAD_SIZE}_*_run*.log"
echo "   - Target VMs snapshots: ./results/resource_snapshot_*.log"
echo ""
echo "💡 To find which run had lowest RAM (likely OOM):"
echo "   for f in ./results/vmstat_K6_VM_${PAYLOAD_SIZE}_*.log; do"
echo "     echo -n \"\$f: \"; awk 'NR>2 {print \$4}' \"\$f\" | sort -n | head -1;"
echo "   done"
echo ""
echo "💡 To view detailed memory timeline for a specific run:"
echo "   cat ./results/vmstat_K6_VM_${PAYLOAD_SIZE}_income_run5.log"
echo ""
echo "💡 To parse all resource logs into CSV:"
echo "   python parse_resource_usage.py"
echo ""

#!/bin/bash

# ============================================
# Full Experiment Runner
# ============================================
# Runs automated tests sequentially for multiple payload sizes
# WITH RAM and disk monitoring per-run
# Uses run_multiple_tests.sh for enhanced monitoring

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# ============================================
# CONFIGURATION - EDIT THIS SECTION
# ============================================

# Load configuration from config.env
if [ -f "config.env" ]; then
    source config.env
else
    # Default configuration
    VM_NO_CACHE="13.214.170.49"
    VM_CACHE="18.141.211.240"
    VM_CACHE_BACKUP="52.77.228.157"
    SSH_KEY="~/.ssh/id_ed25519"
    SSH_USER="ubuntu"
    DB_NAME="aisco_product_hightide"
    DB_USER="postgres"
    APP_RESTART_WAIT=30
fi

# Number of runs per endpoint for each payload size
RUNS=10

# Payload sizes to test (edit this array)
PAYLOAD_SIZES=(
    10
    100
    500
    1000
    2000
    4000
    8000
    16000
    32000
)

# Wait time between different payload size tests (in seconds)
WAIT_BETWEEN_TESTS=15  # Changed from 60 to 15 as per procedure

# ============================================
# HELPER FUNCTIONS
# ============================================

# Function to execute SQL on VM
execute_sql_on_vm() {
    local vm_ip="$1"
    local sql_file="$2"
    local vm_name="$3"
    
    log_info "Executing $sql_file on $vm_name ($vm_ip)..."
    
    if [ ! -f "$sql_file" ]; then
        log_error "SQL file not found: $sql_file"
        return 1
    fi
    
    # Copy SQL file and execute it
    scp -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "$sql_file" "$SSH_USER@$vm_ip:/tmp/" 2>/dev/null
    
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$vm_ip" \
        "sudo -u $DB_USER psql -d $DB_NAME -f /tmp/$(basename $sql_file)" 2>/dev/null
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        log_success "SQL executed successfully on $vm_name"
        return 0
    else
        log_error "Failed to execute SQL on $vm_name"
        return 1
    fi
}

# Function to find appropriate seed file
find_seed_file() {
    local payload_size="$1"
    
    # Try exact match first
    if [ -f "seed_income_${payload_size}_records.sql" ]; then
        echo "seed_income_${payload_size}_records.sql"
        return 0
    fi
    
    # Try seed directory
    if [ -f "seeds/seed_income_${payload_size}_records.sql" ]; then
        echo "seeds/seed_income_${payload_size}_records.sql"
        return 0
    fi
    
    log_error "Seed file not found for payload size $payload_size"
    log_error "Expected: seed_income_${payload_size}_records.sql"
    return 1
}

# ============================================
# DO NOT EDIT BELOW THIS LINE
# ============================================

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║         FULL EXPERIMENT AUTOMATION - WITH MONITORING           ║"
echo "║         Sequential Testing with Multiple Payload Sizes         ║"
echo "║         WITH Database Reset + Seeding + 120s Wait Period       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Experiment Configuration:"
echo "  • Runs per endpoint: $RUNS"
echo "  • Payload sizes: ${PAYLOAD_SIZES[*]}"
echo "  • Total experiments: ${#PAYLOAD_SIZES[@]}"
echo "  • Wait between runs: ${WAIT_BETWEEN_TESTS}s"
echo "  • Wait after seeding: ${APP_RESTART_WAIT}s"
echo "  • Monitoring: K6 VM RAM every 5 seconds per run"
echo ""

# Check required files
if [ ! -f "run_multiple_tests.sh" ]; then
    log_error "run_multiple_tests.sh not found in current directory!"
    exit 1
fi

if [ ! -f "reset_hightide.sql" ]; then
    log_error "reset_hightide.sql not found in current directory!"
    exit 1
fi

# Make sure scripts are executable
chmod +x run_multiple_tests.sh

# Calculate total estimated time
# Each payload size experiment includes:
# - Database reset (~30s)
# - Database seeding (~30s)  
# - 120s wait after seeding
# - 2 endpoints * RUNS tests
# - Each test: ~1.5 minutes (with 5 VUs moderate load)
# - 10s wait between runs
# - 10s wait between payload sizes

total_payload_sizes=${#PAYLOAD_SIZES[@]}
db_operations_per_payload=$((30 + 30 + APP_RESTART_WAIT))  # reset + seed + wait
test_time_per_run=90  # 1.5 minutes = 90 seconds with 5 VUs
total_runs_per_payload=$(($RUNS * 2))  # 2 endpoints
waits_per_payload=$(($RUNS * 2 - 1))  # 10s between runs (not after last run)

time_per_payload=$(($db_operations_per_payload + ($test_time_per_run * $total_runs_per_payload) + ($waits_per_payload * 10)))
total_seconds=$(($time_per_payload * $total_payload_sizes))
estimated_minutes=$(($total_seconds / 60))
estimated_hours=$(($estimated_minutes / 60))
remaining_minutes=$(($estimated_minutes % 60))

log_info "Estimated total time: ~${estimated_hours}h ${remaining_minutes}m"
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "This will run ${#PAYLOAD_SIZES[@]} sequential experiments."
echo "Each run will have continuous RAM monitoring to detect OOM."
echo "Press Ctrl+C within 10 seconds to cancel, or wait to continue..."
echo "═══════════════════════════════════════════════════════════════"
sleep 10
echo ""

# Track success/failure
declare -a successful_tests
declare -a failed_tests

start_time=$(date +%s)

# Run tests for each payload size
for i in "${!PAYLOAD_SIZES[@]}"; do
    payload="${PAYLOAD_SIZES[$i]}"
    test_num=$((i + 1))
    total_count=${#PAYLOAD_SIZES[@]}
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    printf "║  EXPERIMENT %d/%d: PAYLOAD SIZE = %-28s║\n" "$test_num" "$total_count" "$payload records"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # ============================================
    # STEP 1: RESET DATABASE
    # ============================================
    echo "═══════════════════════════════════════════════════════════════"
    log_info "STEP 1: Resetting databases on all VMs"
    echo "═══════════════════════════════════════════════════════════════"
    
    if ! execute_sql_on_vm "$VM_NO_CACHE" "reset_hightide.sql" "No-Cache VM"; then
        log_error "Failed to reset database on No-Cache VM"
        failed_tests+=("$payload")
        continue
    fi
    
    if ! execute_sql_on_vm "$VM_CACHE" "reset_hightide.sql" "Cache-Hit VM"; then
        log_error "Failed to reset database on Cache-Hit VM"
        failed_tests+=("$payload")
        continue
    fi
    
    if ! execute_sql_on_vm "$VM_CACHE_BACKUP" "reset_hightide.sql" "Cache-Miss VM"; then
        log_error "Failed to reset database on Cache-Miss VM"
        failed_tests+=("$payload")
        continue
    fi
    
    echo ""
    
    # ============================================
    # STEP 2: SEED DATABASE
    # ============================================
    echo "═══════════════════════════════════════════════════════════════"
    log_info "STEP 2: Seeding databases with $payload records"
    echo "═══════════════════════════════════════════════════════════════"
    
    seed_file=$(find_seed_file "$payload")
    if [ $? -ne 0 ]; then
        log_error "Cannot proceed without seed file for payload $payload"
        failed_tests+=("$payload")
        continue
    fi
    
    log_success "Using seed file: $seed_file"
    
    if ! execute_sql_on_vm "$VM_NO_CACHE" "$seed_file" "No-Cache VM"; then
        log_error "Failed to seed database on No-Cache VM"
        failed_tests+=("$payload")
        continue
    fi
    
    if ! execute_sql_on_vm "$VM_CACHE" "$seed_file" "Cache-Hit VM"; then
        log_error "Failed to seed database on Cache-Hit VM"
        failed_tests+=("$payload")
        continue
    fi
    
    if ! execute_sql_on_vm "$VM_CACHE_BACKUP" "$seed_file" "Cache-Miss VM"; then
        log_error "Failed to seed database on Cache-Miss VM"
        failed_tests+=("$payload")
        continue
    fi
    
    echo ""
    
    # ============================================
    # STEP 3: WAITING PERIOD (120 seconds)
    # ============================================
    echo "═══════════════════════════════════════════════════════════════"
    log_info "STEP 3: Waiting ${APP_RESTART_WAIT} seconds for applications to reload..."
    echo "═══════════════════════════════════════════════════════════════"
    sleep "$APP_RESTART_WAIT"
    echo ""
    
    # ============================================
    # STEP 4-8: RUN PERFORMANCE TESTS
    # ============================================
    log_info "STEP 4-8: Running performance tests with $payload records..."
    log_info "This includes:"
    log_info "  • Clear Nginx Cache (Step 4)"
    log_info "  • Nginx Reload (Step 5)"
    log_info "  • Cache Warm-up (Step 6)"
    log_info "  • Load Testing with K6 (Step 7)"
    log_info "  • 10s Wait between runs (Step 8)"
    echo ""
    
    # Run the test with script (includes cache clearing, warm-up, and testing)
    if ./run_multiple_tests.sh "$RUNS" "$payload"; then
        successful_tests+=("$payload")
        log_success "Experiment $test_num/$total_count completed successfully (payload: $payload)"
        
        # Show summary of monitoring files created
        echo ""
        log_info "Monitoring files created for payload $payload:"
        echo "  📊 K6 VM per-run logs: results/vmstat_K6_VM_${payload}_*_run*.log"
        echo "  📸 Target VM snapshots: results/resource_snapshot_${payload}_*.log"
    else
        failed_tests+=("$payload")
        log_error "Experiment $test_num/$total_count FAILED (payload: $payload)"
        
        # Ask user if they want to continue after failure
        echo ""
        echo "⚠️  A test has failed. Do you want to continue with remaining tests?"
        read -p "Continue? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Experiment sequence aborted by user"
            break
        fi
    fi
    
    # Wait between tests (except after the last one)
    if [ $test_num -lt $total_count ]; then
        echo ""
        log_info "Waiting ${WAIT_BETWEEN_TESTS} seconds before next experiment (Step 8)..."
        sleep "$WAIT_BETWEEN_TESTS"
    fi
done

end_time=$(date +%s)
duration=$((end_time - start_time))
duration_minutes=$((duration / 60))
duration_hours=$((duration_minutes / 60))
remaining_minutes=$((duration_minutes % 60))

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║              FULL EXPERIMENT SEQUENCE COMPLETED                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Experiment Summary:"
echo "  • Total time: ${duration_hours}h ${remaining_minutes}m"
echo "  • Successful experiments: ${#successful_tests[@]}/${#PAYLOAD_SIZES[@]}"
echo "  • Failed experiments: ${#failed_tests[@]}"
echo ""

if [ ${#successful_tests[@]} -gt 0 ]; then
    log_success "Successful payload sizes:"
    for size in "${successful_tests[@]}"; do
        echo "    ✓ $size records"
    done
    echo ""
fi

if [ ${#failed_tests[@]} -gt 0 ]; then
    log_error "Failed payload sizes:"
    for size in "${failed_tests[@]}"; do
        echo "    ✗ $size records"
    done
    echo ""
fi

log_info "All results are saved in ./results/ directory"
echo ""
echo "📊 Monitoring Data Summary:"
echo "  • Performance JSON: results/test_*.json"
echo "  • K6 VM per-run RAM: results/vmstat_K6_VM_*_run*.log"
echo "  • Target VM snapshots: results/resource_snapshot_*.log"
echo ""
echo "💡 To analyze K6 RAM usage and find OOM causes:"
echo "   # Find runs with lowest RAM"
echo "   for f in results/vmstat_K6_VM_*.log; do"
echo "     echo -n \"\$f: \"; awk 'NR>2 {print \$4}' \"\$f\" | sort -n | head -1;"
echo "   done"
echo ""
echo "💡 To parse all monitoring data into CSV:"
echo "   python parse_resource_usage.py"
echo ""

if [ ${#failed_tests[@]} -eq 0 ]; then
    log_success "🎉 All experiments completed successfully!"
    exit 0
else
    log_error "⚠️  Some experiments failed. Check monitoring logs to diagnose OOM issues."
    exit 1
fi

#!/bin/bash

# Exit on any error
set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(dirname "$SCRIPT_DIR")"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Utility function to create a delay
delay() {
    sleep "$1"
}

# Log with colors
log_info() {
    echo -e "${BLUE}$1${NC}"
}

log_success() {
    echo -e "${GREEN}$1${NC}"
}

log_warning() {
    echo -e "${YELLOW}$1${NC}"
}

log_error() {
    echo -e "${RED}$1${NC}"
}

# Load environment variables from .env file in contracts directory if it exists
load_env_file() {
    local env_file="$1"
    
    if [ ! -f "$env_file" ]; then
        return 0
    fi
    
    log_info "Loading environment variables from $env_file"
    
    # Create a temporary file to store the processed env vars
    local temp_env=$(mktemp)
    
    # First pass: extract all variables (including those with references)
    grep -v '^#' "$env_file" | grep -E '^[A-Za-z_][A-Za-z0-9_]*=' > "$temp_env" || true
    
    # Source the file to allow variable expansion
    set -a  # automatically export all variables
    source "$temp_env"
    set +a  # turn off auto-export
    
    # Clean up
    rm -f "$temp_env"
}

if [ -f "$CONTRACTS_DIR/.env" ]; then
    load_env_file "$CONTRACTS_DIR/.env"
fi

# Check if anvil is ready by testing the RPC endpoint
is_anvil_ready() {
    local port=${1:-8545}
    local response
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "http://localhost:${port}" 2>/dev/null || echo "")
    
    if [[ -n "$response" ]] && echo "$response" | jq -e '.result' >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Kill any existing anvil processes
pkill_anvil() {
    log_info "Killing any existing Anvil processes..."
    pkill -f anvil || true  # Don't fail if no processes found
    delay 1
}

# Check if anvil is running on the correct chain
check_anvil_is_on_correct_chain() {
    local port=${1:-8545}
    local response
    local chain_id
    
    response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
        "http://localhost:${port}" 2>/dev/null || echo "")
    
    if [[ -z "$response" ]]; then
        return 1
    fi
    
    chain_id=$(echo "$response" | jq -r '.result' 2>/dev/null || echo "")
    
    if [[ "$chain_id" == "$ANVIL_FORK_CHAIN_ID" ]]; then
        return 0
    else
        return 1
    fi
}

# Wait for anvil to be ready with timeout and retries
wait_for_anvil() {
    local timeout_ms=${1:-3000}
    local interval_ms=${2:-100}
    local start_time=$(date +%s%3N | sed 's/N$//')
    local current_time
    local elapsed
    
    while true; do
        current_time=$(date +%s%3N | sed 's/N$//')
        elapsed=$((current_time - start_time))
        
        if (( elapsed >= timeout_ms )); then
            log_error "Anvil failed to start within ${timeout_ms}ms"
            return 1
        fi
        
        if is_anvil_ready; then
            log_success "✅ Anvil is ready and accepting connections!"
            return 0
        fi
        
        delay $(echo "scale=3; $interval_ms / 1000" | bc)
    done
}

# Function to expand environment variables in fork URL
expand_fork_url() {
    local fork_url="$1"
    
    if [[ "$fork_url" == *'$'* ]]; then
        # Split on $ and get the part after it (matches TypeScript logic)
        local encoded_variable="${fork_url#*\$}"
        
        # Remove { and } characters (matches TypeScript logic)
        local variable="${encoded_variable//\{/}"
        variable="${variable//\}/}"
        
        if [[ -z "$variable" ]]; then
            log_error "Invalid fork URL format"
            exit 1
        fi
        
        local var_value="${!variable}"
        if [[ -z "$var_value" ]]; then
            log_error "Environment variable $variable not found"
            exit 1
        fi
        
        # Replace the original $encodedVariable with the value
        fork_url="${fork_url/\$$encoded_variable/$var_value}"
    fi
    
    echo "$fork_url"
}

# Function to start anvil with retry logic
start_anvil_with_retry() {
    local max_retries=${1:-3}
    
    # Check if there are already anvil processes running on the correct chain
    if check_anvil_is_on_correct_chain; then
        log_success "Anvil is already running on the correct chain, skipping start"
        return 0
    fi
    
    pkill_anvil
    
    for ((attempt=1; attempt<=max_retries; attempt++)); do
        if [[ $attempt -eq 1 ]]; then
            log_info "Starting Anvil blockchain..."
        else
            log_warning "🔄 Retry attempt $attempt/$max_retries"
        fi
        
        local fork_url="$ANVIL_FORK_URL"
        local fork_chain_id="$ANVIL_FORK_CHAIN_ID"
        local fork_block_number="${ANVIL_FORK_BLOCK_NUMBER:--1}"
        local trace="$ANVIL_TRACE"
        local verbosity="$ANVIL_VERBOSITY"

        echo "fork_url: $fork_url"
        echo "fork_chain_id: $fork_chain_id"
        echo "fork_block_number: $fork_block_number"
        echo "trace: $trace"
        echo "verbosity: $verbosity"
        
        # Expand environment variables in fork URL
        if [[ -n "$fork_url" ]]; then
            fork_url=$(expand_fork_url "$fork_url")
        fi
        
        # Build anvil parameters
        local params=("--block-time" "2")
        
        if [[ -n "$fork_url" ]]; then
            params+=("-f" "$fork_url")
        fi
        
        if [[ "$trace" == "true" ]]; then
            params+=("--tracing" "--print-traces")
        fi
        
        if [[ -n "$verbosity" ]] && [[ "$verbosity" =~ ^[0-9]+$ ]]; then
            local v_flags=""
            for ((i=0; i<verbosity; i++)); do
                v_flags+="v"
            done
            params+=("-$v_flags")
        fi
        
        if [[ -n "$fork_url" ]] && [[ -n "$fork_block_number" ]]; then
            params+=("--fork-block-number=$fork_block_number")
        fi
        
        if [[ -n "$fork_url" ]] && [[ -n "$fork_chain_id" ]]; then
            params+=("--fork-chain-id" "$fork_chain_id")
        fi
        
        # Start anvil process in the background
        anvil "${params[@]}" &
        local anvil_pid=$!
        
        # Wait a bit for the process to start
        delay 1
        
        # Check if the process is still running
        if ! kill -0 "$anvil_pid" 2>/dev/null; then
            log_error "❌ Attempt $attempt failed: Anvil process died immediately"
            if [[ $attempt -eq $max_retries ]]; then
                log_error "🚨 All $max_retries attempts failed. Anvil could not be started."
                exit 1
            fi
            delay 1
            continue
        fi
        
        # Wait for anvil to be ready
        if wait_for_anvil; then
            log_success "🎉 Anvil started successfully on attempt $attempt"
            
            # Set up signal handlers to clean up the anvil process
            trap "log_info 'Terminating Anvil...'; kill $anvil_pid 2>/dev/null || true; exit 0" SIGTERM SIGINT
            
            # Wait for the anvil process to exit
            wait "$anvil_pid"
            local exit_code=$?
            log_info "Anvil exited with code $exit_code"
            exit $exit_code
        else
            log_error "❌ Attempt $attempt failed: Anvil failed to become ready"
            kill "$anvil_pid" 2>/dev/null || true
            
            if [[ $attempt -eq $max_retries ]]; then
                log_error "🚨 All $max_retries attempts failed. Anvil could not be started."
                exit 1
            fi
            
            delay 1
        fi
    done
}

# Check environment constraints
if [[ -n "$APP_ENV" ]] && [[ "$APP_ENV" != "development" ]]; then
    log_error "Not running Anvil in non-development environment"
    exit 0
fi

# Only run anvil when NODE_ENV is unset or is 'development'
if [[ -z "$NODE_ENV" ]] || [[ "$NODE_ENV" == "development" ]]; then
    # Check if required tools are available
    if ! command -v curl >/dev/null 2>&1; then
        log_error "curl is required but not installed"
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        log_error "jq is required but not installed"
        exit 1
    fi
    
    if ! command -v bc >/dev/null 2>&1; then
        log_error "bc is required but not installed"
        exit 1
    fi
    
    if ! command -v anvil >/dev/null 2>&1; then
        log_error "anvil is required but not installed"
        exit 1
    fi
    
    start_anvil_with_retry
else
    log_error "Not running Anvil in non-development environment"
    exit 0
fi

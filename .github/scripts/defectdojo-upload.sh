#!/bin/bash

set -e


# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color


DEFECTDOJO_URL="${DEFECTDOJO_URL}"
DEFECTDOJO_API_TOKEN="${DEFECTDOJO_API_TOKEN}"
PRODUCT_NAME="${PRODUCT_NAME:-OWASP Juice Shop}"
PRODUCT_DESCRIPTION="${PRODUCT_DESCRIPTION:-OWASP Juice Shop - Automated DevSecOps Pipeline}"
ENGAGEMENT_NAME="${ENGAGEMENT_NAME:-CI/CD Run}"
BUILD_ID="${BUILD_ID}"
COMMIT_HASH="${COMMIT_HASH}"
BRANCH_TAG="${BRANCH_TAG}"
SOURCE_CODE_MANAGEMENT_URI="${SOURCE_CODE_MANAGEMENT_URI}"


log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}


api_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    local is_multipart=$4

    local url="${DEFECTDOJO_URL}/api/v2/${endpoint}"
    
    if [ "$is_multipart" = "true" ]; then
        curl -s -X "${method}" "${url}" \
            -H "Authorization: Token ${DEFECTDOJO_API_TOKEN}" \
            ${data}
    else
        curl -s -X "${method}" "${url}" \
            -H "Authorization: Token ${DEFECTDOJO_API_TOKEN}" \
            -H "Content-Type: application/json" \
            -d "${data}"
    fi
}


find_or_create_product() {
    log_info "Checking if product '${PRODUCT_NAME}' exists..."
    
    local encoded_product_name=$(echo "${PRODUCT_NAME}" | jq -sRr @uri)
    local response=$(api_request "GET" "products/?name=${encoded_product_name}" "" "false")
    
    local count=$(echo "${response}" | jq -r '.count // 0')
    
    if [ "$count" -gt 0 ]; then
        local product_id=$(echo "${response}" | jq -r '.results[0].id')
        log_info "Product found with ID: ${product_id}"
        echo "${product_id}"
    else
        log_info "Product not found. Creating new product..."
        
        local product_data=$(jq -n \
            --arg name "${PRODUCT_NAME}" \
            --arg desc "${PRODUCT_DESCRIPTION}" \
            '{
                name: $name,
                description: $desc,
                prod_type: 1
            }')
        
        response=$(api_request "POST" "products/" "${product_data}" "false")
        local product_id=$(echo "${response}" | jq -r '.id')
        
        if [ -z "$product_id" ] || [ "$product_id" = "null" ]; then
            log_error "Failed to create product. Response: ${response}"
            exit 1
        fi
        
        log_info "Product created with ID: ${product_id}"
        echo "${product_id}"
    fi
}


create_engagement() {
    local product_id=$1
    local today=$(date +%Y-%m-%d)
    
    log_info "Creating engagement for product ID: ${product_id}..."
    
    local engagement_data=$(jq -n \
        --arg name "${ENGAGEMENT_NAME}" \
        --arg product "${product_id}" \
        --arg start "${today}" \
        --arg end "${today}" \
        --arg build_id "${BUILD_ID}" \
        --arg commit_hash "${COMMIT_HASH}" \
        --arg branch_tag "${BRANCH_TAG}" \
        --arg source_uri "${SOURCE_CODE_MANAGEMENT_URI}" \
        '{
            name: $name,
            product: ($product | tonumber),
            engagement_type: "CI/CD",
            target_start: $start,
            target_end: $end,
            status: "In Progress",
            build_id: $build_id,
            commit_hash: $commit_hash,
            branch_tag: $branch_tag,
            source_code_management_uri: $source_uri
        }')
    
    local response=$(api_request "POST" "engagements/" "${engagement_data}" "false")
    local engagement_id=$(echo "${response}" | jq -r '.id')
    
    if [ -z "$engagement_id" ] || [ "$engagement_id" = "null" ]; then
        log_error "Failed to create engagement. Response: ${response}"
        exit 1
    fi
    
    log_info "Engagement created with ID: ${engagement_id}"
    echo "${engagement_id}"
}


import_scan() {
    local engagement_id=$1
    local scan_file=$2
    local scan_type=$3
    local scan_name=$4
    
    if [ ! -f "${scan_file}" ]; then
        log_warn "Scan file not found: ${scan_file} - Skipping..."
        return 0
    fi
    
    log_info "Importing ${scan_name} scan from: ${scan_file}"
    
    local form_data="-F \"scan_type=${scan_type}\" \
        -F \"file=@${scan_file}\" \
        -F \"engagement=${engagement_id}\" \
        -F \"minimum_severity=Info\" \
        -F \"active=true\" \
        -F \"verified=false\" \
        -F \"scan_date=$(date +%Y-%m-%d)\""
    
    local response=$(api_request "POST" "import-scan/" "${form_data}" "true")
    
    local test_id=$(echo "${response}" | jq -r '.test // .id // empty')
    
    if [ -n "$test_id" ] && [ "$test_id" != "null" ]; then
        log_info "${scan_name} scan imported successfully (Test ID: ${test_id})"
        return 0
    else
        log_warn "Failed to import ${scan_name} scan. Response: ${response}"
        return 1
    fi
}

close_engagement() {
    local engagement_id=$1
    
    log_info "Closing engagement ID: ${engagement_id}..."
    
    local engagement_data='{"status": "Completed"}'
    
    local response=$(api_request "PATCH" "engagements/${engagement_id}/" "${engagement_data}" "false")
    local status=$(echo "${response}" | jq -r '.status // empty')
    
    if [ "$status" = "Completed" ]; then
        log_info "Engagement closed successfully"
        return 0
    else
        log_warn "Failed to close engagement. Response: ${response}"
        return 1
    fi
}


main() {
    log_info "Starting DefectDojo upload process..."
    
    # Validate required environment variables
    if [ -z "$DEFECTDOJO_URL" ] || [ -z "$DEFECTDOJO_API_TOKEN" ]; then
        log_error "Missing required environment variables: DEFECTDOJO_URL and/or DEFECTDOJO_API_TOKEN"
        exit 1
    fi
    
    # Step 1: Find or create product
    PRODUCT_ID=$(find_or_create_product)
    
    # Step 2: Create engagement
    ENGAGEMENT_ID=$(create_engagement "$PRODUCT_ID")
    
    # Step 3: Import all scan results
    log_info "Importing scan results..."
    
    import_scan "$ENGAGEMENT_ID" "semgrep-results.json" "Semgrep JSON Report" "Semgrep" || true
    import_scan "$ENGAGEMENT_ID" "bandit-results.json" "Bandit Scan" "Bandit" || true
    import_scan "$ENGAGEMENT_ID" "trivy-fs-results.json" "Trivy Scan" "Trivy Filesystem" || true
    import_scan "$ENGAGEMENT_ID" "trivy-image-results.json" "Trivy Scan" "Trivy Image" || true
    import_scan "$ENGAGEMENT_ID" "zap-results.json" "ZAP Scan" "OWASP ZAP" || true
    import_scan "$ENGAGEMENT_ID" "dependency-check-report.xml" "Dependency Check Scan" "OWASP Dependency-Check" || true
    
    # Step 4: Close engagement
    close_engagement "$ENGAGEMENT_ID"
    
    log_info "DefectDojo upload process completed successfully!"
    log_info "View results at: ${DEFECTDOJO_URL}/engagement/${ENGAGEMENT_ID}"
}

# Run main function
main

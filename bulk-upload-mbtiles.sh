#!/bin/bash

# Bulk Upload MBTiles to MinIO and Insert to PostgreSQL
# Usage: ./bulk-upload-mbtiles.sh <source_folder> [options]
#
# Options:
#   --status <status>       Set status (default: "Dalam Proses")
#   --operator <name>       Set operator name
#   --location <location>   Set location label
#   --bpdas <code>          Set BPDAS code
#   --dry-run              Show what would be done without executing
#
# Example:
#   ./bulk-upload-mbtiles.sh /path/to/mbtiles --status "Aktif" --operator "Team A"

set -e

# =============================================================================
# Configuration
# =============================================================================

# MinIO Configuration
S3_HOST="${S3_HOST:-http://52.76.171.132:9005}"
S3_BUCKET="${S3_BUCKET:-idpm}"
S3_PATH="${S3_PATH:-layers/drone/mbtiles}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-eY7VQA55gjPQu1CGv540}"
S3_SECRET_KEY="${S3_SECRET_KEY:-u6feeKC1s8ttqU1PLLILrfyqdv79UOvBkzpWhIIn}"
S3_HOSTNAME="${S3_HOSTNAME:-https://api-minio.ptnaghayasha.com}"

# Webhook Configuration
WEBHOOK_URL="${WEBHOOK_URL:-https://api.ptnaghayasha.com/api/minio-webhook}"
WEBHOOK_ENABLED="${WEBHOOK_ENABLED:-true}"

# PostgreSQL Configuration
DB_HOST="${DB_HOST:-52.74.112.75}"
DB_PORT="${DB_PORT:-5432}"
DB_NAME="${DB_NAME:-postgres}"
DB_USER="${DB_USER:-pg}"
DB_PASSWORD="${DB_PASSWORD:-~nagha2025yasha@~}"
DB_TABLE="geoportal.pmn_drone_imagery"

# Default values
DEFAULT_STATUS="Dalam Proses"
DEFAULT_OPERATOR=""
DEFAULT_LOCATION=""
DEFAULT_BPDAS=""
DRY_RUN=false

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_success() {
    echo "[SUCCESS] ✓ $*" >&2
}

log_error() {
    echo "[ERROR] ✗ $*" >&2
}

log_warn() {
    echo "[WARN] ⚠ $*" >&2
}

# Generate unique ID
generate_id() {
    local timestamp=$(date +%s%3N)
    local random=$(openssl rand -hex 4 | tr '[:lower:]' '[:upper:]')
    echo "DRN-${random}"
}

# Get file size in MB
get_file_size_mb() {
    local file="$1"
    local size_bytes=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    echo "scale=2; $size_bytes / 1024 / 1024" | bc
}

# Get file size label
get_file_size_label() {
    local file="$1"
    local size_mb=$(get_file_size_mb "$file")
    echo "${size_mb} MB"
}

# Validate MBTiles file
is_valid_mbtiles() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        return 1
    fi
    
    if [ ! -r "$file" ]; then
        log_error "File not readable: $file"
        return 1
    fi
    
    # Check if it's a valid SQLite database
    if ! sqlite3 "$file" ".tables" 2>/dev/null | grep -q "tiles"; then
        log_error "Invalid MBTiles file (no tiles table): $file"
        return 1
    fi
    
    # Check if it has tiles
    local tile_count=$(sqlite3 "$file" "SELECT COUNT(*) FROM tiles;" 2>/dev/null || echo "0")
    if [ "$tile_count" -eq 0 ]; then
        log_error "MBTiles file has no tiles: $file"
        return 1
    fi
    
    return 0
}

# Generate title from filename
generate_title() {
    local filename="$1"
    # Remove extension
    local title=$(basename "$filename" .mbtiles)
    # Replace underscores and hyphens with spaces
    title=$(echo "$title" | sed 's/[_-]/ /g')
    # Remove multiple spaces
    title=$(echo "$title" | sed 's/  */ /g')
    # Trim
    title=$(echo "$title" | sed 's/^ *//;s/ *$//')
    
    if [ -z "$title" ]; then
        title="Citra Drone"
    fi
    
    echo "$title"
}

# Check if mc (MinIO Client) is installed
check_mc() {
    if ! command -v mc >/dev/null 2>&1; then
        log_error "mc (MinIO Client) not found. Please install it first."
        log_info "Installation: https://min.io/docs/minio/linux/reference/minio-mc.html"
        exit 1
    fi
}

# Check if psql is installed
check_psql() {
    if ! command -v psql >/dev/null 2>&1; then
        log_error "psql (PostgreSQL client) not found. Please install it first."
        log_info "Installation: sudo apt-get install postgresql-client"
        exit 1
    fi
}

# Configure MinIO client
configure_minio() {
    local alias_name="bulk_upload_minio"
    
    log_info "Configuring MinIO client..."
    if mc alias set "$alias_name" "$S3_HOST" "$S3_ACCESS_KEY" "$S3_SECRET_KEY" --insecure >/dev/null 2>&1; then
        log_success "MinIO client configured"
        echo "$alias_name"
    else
        log_error "Failed to configure MinIO client"
        exit 1
    fi
}

# Check if file exists in MinIO
check_minio_exists() {
    local alias_name="$1"
    local filename="$2"
    
    if mc stat "$alias_name/$S3_BUCKET/$S3_PATH/$filename" --insecure >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Check if file exists in database by storage path
check_database_exists() {
    local storage_path="$1"
    
    local sql="SELECT id FROM $DB_TABLE WHERE storage_path = '$storage_path' LIMIT 1;"
    
    if [ -n "$DB_PASSWORD" ]; then
        export PGPASSWORD="$DB_PASSWORD"
    fi
    
    local result=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "$sql" 2>&1)
    local exit_code=$?
    
    unset PGPASSWORD
    
    if [ $exit_code -eq 0 ] && [ -n "$(echo "$result" | tr -d '[:space:]')" ]; then
        return 0
    else
        return 1
    fi
}

# Generate timestamp prefix for filename
generate_timestamp_prefix() {
    date +%s%3N
}

# Trigger webhook notification (simulates MinIO event)
trigger_webhook() {
    local filename="$1"
    
    if [ "$WEBHOOK_ENABLED" != "true" ]; then
        return 0
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_info "DRY RUN: Would trigger webhook for $filename"
        return 0
    fi
    
    log_info "Triggering webhook for: $filename"
    
    # Create MinIO-compatible webhook payload
    local payload=$(cat <<EOF
{
  "EventName": "s3:ObjectCreated:Put",
  "Key": "$S3_BUCKET/$S3_PATH/$filename",
  "Records": [{
    "eventVersion": "2.0",
    "eventSource": "minio:s3",
    "eventName": "s3:ObjectCreated:Put",
    "s3": {
      "configurationId": "Config",
      "bucket": {
        "name": "$S3_BUCKET",
        "arn": "arn:aws:s3:::$S3_BUCKET"
      },
      "object": {
        "key": "$S3_PATH/$filename",
        "size": 0,
        "contentType": "application/octet-stream"
      }
    }
  }]
}
EOF
)
    
    # Send webhook request
    local response=$(curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -H "User-Agent: MinIO" \
        -d "$payload" \
        --silent \
        --write-out "\n%{http_code}" \
        --max-time 10 \
        2>&1)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        log_success "Webhook triggered successfully (HTTP $http_code)"
        return 0
    else
        log_warn "Webhook returned HTTP $http_code"
        log_warn "Response: $body"
        return 0  # Don't fail the upload if webhook fails
    fi
}

# Upload file to MinIO
upload_to_minio() {
    local file="$1"
    local alias_name="$2"
    local filename="$3"  # filename with timestamp prefix
    
    log_info "Uploading: $filename ($(get_file_size_label "$file"))"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN: Would upload $filename to MinIO"
        echo "$S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$filename"
        return 0
    fi
    
    # Upload file with clean output capture
    local upload_output=$(mc cp "$file" "$alias_name/$S3_BUCKET/$S3_PATH/$filename" --insecure 2>&1)
    local upload_exit=$?
    
    if [ $upload_exit -eq 0 ]; then
        # Construct the final URL (MinIO doesn't return it directly)
        local file_url="$S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$filename"
        log_success "Uploaded: $filename"
        echo "$file_url"
        return 0
    else
        log_error "Failed to upload: $filename"
        log_error "Error output: $upload_output"
        return 1
    fi
}

# Insert record to PostgreSQL
insert_to_database() {
    local id="$1"
    local title="$2"
    local filename="$3"
    local file_size_label="$4"
    local storage_path="$5"
    local status="$6"
    local operator="$7"
    local location="$8"
    local bpdas="$9"
    
    log_info "Inserting to database: $id"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY RUN: Would insert record to database"
        log_info "  ID: $id"
        log_info "  Title: $title"
        log_info "  File: $filename"
        log_info "  Size: $file_size_label"
        log_info "  Storage: $storage_path"
        log_info "  Status: $status"
        return 0
    fi
    
    # Prepare SQL
    local sql="
        INSERT INTO $DB_TABLE (
            id,
            title,
            thumbnail_url,
            captured_at,
            captured_display,
            location_label,
            bpdas,
            format_label,
            file_size_label,
            operator_name,
            mission_summary,
            weather_notes,
            status,
            notes,
            storage_path,
            map_preview_url
        )
        VALUES (
            '$id',
            '$title',
            NULL,
            NULL,
            NULL,
            $([ -n "$location" ] && echo "'$location'" || echo "NULL"),
            $([ -n "$bpdas" ] && echo "'$bpdas'" || echo "NULL"),
            'MBTILES',
            '$file_size_label',
            $([ -n "$operator" ] && echo "'$operator'" || echo "NULL"),
            NULL,
            NULL,
            '$status'::pmn_drone_status,
            'Bulk upload otomatis dari berkas $filename',
            '$storage_path',
            NULL
        )
        ON CONFLICT (id) DO NOTHING
        RETURNING id;
    "
    
    # Execute SQL
    local result
    if [ -n "$DB_PASSWORD" ]; then
        export PGPASSWORD="$DB_PASSWORD"
    fi
    
    result=$(psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "$sql" 2>&1)
    local exit_code=$?
    
    unset PGPASSWORD
    
    if [ $exit_code -eq 0 ] && echo "$result" | grep -q "$id"; then
        log_success "Inserted to database: $id"
        return 0
    elif echo "$result" | grep -q "duplicate key"; then
        log_warn "Record already exists in database: $id"
        return 0
    else
        log_error "Failed to insert to database: $result"
        return 1
    fi
}

# Process single file
process_file() {
    local file="$1"
    local alias_name="$2"
    local status="$3"
    local operator="$4"
    local location="$5"
    local bpdas="$6"
    
    local original_filename=$(basename "$file")
    
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    log_info "Processing: $original_filename"
    echo "═══════════════════════════════════════════════════════════════"
    
    # Validate file
    if ! is_valid_mbtiles "$file"; then
        log_error "Skipping invalid file: $original_filename"
        return 1
    fi
    
    # Generate timestamp prefix and new filename
    local timestamp_prefix=$(generate_timestamp_prefix)
    local filename="${timestamp_prefix}_${original_filename}"
    
    log_info "New filename with timestamp: $filename"
    
    # Check if file already exists in MinIO
    if check_minio_exists "$alias_name" "$filename"; then
        log_warn "File already exists in MinIO: $filename"
        
        # Construct storage path and check database
        local existing_storage_path="$S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$filename"
        if check_database_exists "$existing_storage_path"; then
            log_warn "File also exists in database, skipping: $filename"
            return 2  # Return 2 to indicate skipped
        else
            log_info "File exists in MinIO but not in database, will insert to database"
        fi
    fi
    
    # Generate metadata
    local id=$(generate_id)
    local title=$(generate_title "$original_filename")
    local file_size_label=$(get_file_size_label "$file")
    
    log_info "ID: $id"
    log_info "Title: $title"
    log_info "Size: $file_size_label"
    
    # Upload to MinIO only if it doesn't exist
    local storage_path
    if check_minio_exists "$alias_name" "$filename"; then
        storage_path="$S3_HOSTNAME/$S3_BUCKET/$S3_PATH/$filename"
        log_info "Using existing file in MinIO: $filename"
    else
        storage_path=$(upload_to_minio "$file" "$alias_name" "$filename")
        
        if [ $? -ne 0 ]; then
            log_error "Upload failed, skipping database insert"
            return 1
        fi
        
        # Verify upload completed successfully
        if ! check_minio_exists "$alias_name" "$filename"; then
            log_error "Upload verification failed: file not found in MinIO after upload"
            return 1
        fi
        log_success "Upload verified: $filename"
        
        # Trigger webhook after successful upload
        trigger_webhook "$filename"
    fi
    
    # Check again if database record exists with this storage path
    if check_database_exists "$storage_path"; then
        log_warn "Record already exists in database for: $storage_path"
        log_info "Completed (already exists): $filename"
        return 2  # Return 2 to indicate skipped
    fi
    
    # Insert to database
    if insert_to_database "$id" "$title" "$original_filename" "$file_size_label" "$storage_path" "$status" "$operator" "$location" "$bpdas"; then
        log_success "Completed: $filename"
        return 0
    else
        log_error "Database insert failed for: $filename"
        return 1
    fi
}

# =============================================================================
# Main Script
# =============================================================================

# Show usage
usage() {
    cat << EOF
Usage: $0 <source_folder> [options]

Bulk upload MBTiles files to MinIO and insert records to PostgreSQL database.

Arguments:
  source_folder           Path to folder containing .mbtiles files

Options:
  --status <status>       Set status for all uploads
                          Valid: "Aktif", "Perlu Review", "Arsip", "Dalam Proses", "Butuh Perbaikan"
                          Default: "Dalam Proses"
  
  --operator <name>       Set operator name for all uploads
  
  --location <location>   Set location label for all uploads
  
  --bpdas <code>          Set BPDAS code for all uploads (will be converted to uppercase)
  
  --dry-run              Show what would be done without actually uploading or inserting
  
  --help                 Show this help message

Environment Variables (optional):
  S3_HOST                MinIO server URL (default: http://52.76.171.132:9005)
  S3_BUCKET              MinIO bucket name (default: idpm)
  S3_PATH                MinIO path prefix (default: layers/drone/mbtiles)
  S3_ACCESS_KEY          MinIO access key
  S3_SECRET_KEY          MinIO secret key
  S3_HOSTNAME            Public MinIO hostname (default: https://api-minio.ptnaghayasha.com)
  
  DB_HOST                PostgreSQL host (default: 52.74.112.75)
  DB_PORT                PostgreSQL port (default: 5432)
  DB_NAME                PostgreSQL database (default: postgres)
  DB_USER                PostgreSQL user (default: postgres)
  DB_PASSWORD            PostgreSQL password

Examples:
  # Basic usage
  $0 /path/to/mbtiles

  # With custom status and operator
  $0 /path/to/mbtiles --status "Aktif" --operator "Team Survey"

  # With all metadata
  $0 /path/to/mbtiles --status "Aktif" --operator "Team A" --location "Kalimantan" --bpdas "BWS01"

  # Dry run to test
  $0 /path/to/mbtiles --dry-run

EOF
    exit 0
}

# Parse arguments
SOURCE_FOLDER=""
STATUS="$DEFAULT_STATUS"
OPERATOR="$DEFAULT_OPERATOR"
LOCATION="$DEFAULT_LOCATION"
BPDAS="$DEFAULT_BPDAS"

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            usage
            ;;
        --status)
            STATUS="$2"
            shift 2
            ;;
        --operator)
            OPERATOR="$2"
            shift 2
            ;;
        --location)
            LOCATION="$2"
            shift 2
            ;;
        --bpdas)
            BPDAS=$(echo "$2" | tr '[:lower:]' '[:upper:]')
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        *)
            if [ -z "$SOURCE_FOLDER" ]; then
                SOURCE_FOLDER="$1"
            else
                log_error "Unknown argument: $1"
                usage
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [ -z "$SOURCE_FOLDER" ]; then
    log_error "Source folder is required"
    usage
fi

if [ ! -d "$SOURCE_FOLDER" ]; then
    log_error "Source folder does not exist: $SOURCE_FOLDER"
    exit 1
fi

# Validate status
case "$STATUS" in
    "Aktif"|"Perlu Review"|"Arsip"|"Dalam Proses"|"Butuh Perbaikan")
        ;;
    *)
        log_error "Invalid status: $STATUS"
        log_info "Valid statuses: Aktif, Perlu Review, Arsip, Dalam Proses, Butuh Perbaikan"
        exit 1
        ;;
esac

# Show configuration
echo "═══════════════════════════════════════════════════════════════"
echo "  Bulk Upload MBTiles to MinIO & PostgreSQL"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Source Folder: $SOURCE_FOLDER"
echo "  Status: $STATUS"
echo "  Operator: ${OPERATOR:-<not set>}"
echo "  Location: ${LOCATION:-<not set>}"
echo "  BPDAS: ${BPDAS:-<not set>}"
echo "  Dry Run: $DRY_RUN"
echo ""
echo "MinIO:"
echo "  Host: $S3_HOST"
echo "  Bucket: $S3_BUCKET"
echo "  Path: $S3_PATH"
echo "  Public URL: $S3_HOSTNAME/$S3_BUCKET/$S3_PATH/"
echo ""
echo "PostgreSQL:"
echo "  Host: $DB_HOST:$DB_PORT"
echo "  Database: $DB_NAME"
echo "  Table: $DB_TABLE"
echo ""

# Check dependencies
if [ "$DRY_RUN" = false ]; then
    check_mc
    check_psql
fi

# Configure MinIO
MC_ALIAS=$(configure_minio)

# Find all MBTiles files
log_info "Scanning for MBTiles files in: $SOURCE_FOLDER"
MBTILES_FILES=$(find "$SOURCE_FOLDER" -maxdepth 1 -type f -name "*.mbtiles" | sort)
FILE_COUNT=$(echo "$MBTILES_FILES" | grep -c .)

if [ -z "$MBTILES_FILES" ] || [ "$FILE_COUNT" -eq 0 ]; then
    log_error "No MBTiles files found in: $SOURCE_FOLDER"
    exit 1
fi

log_info "Found $FILE_COUNT MBTiles file(s)"
echo ""

# Process files
SUCCESS_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

for file in $MBTILES_FILES; do
    process_file "$file" "$MC_ALIAS" "$STATUS" "$OPERATOR" "$LOCATION" "$BPDAS"
    exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    elif [ $exit_code -eq 2 ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
done

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  SUMMARY"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Total files: $FILE_COUNT"
echo "✓ Success: $SUCCESS_COUNT"
echo "⊙ Skipped: $SKIPPED_COUNT"
echo "✗ Failed: $FAILED_COUNT"
echo ""

if [ "$DRY_RUN" = true ]; then
    log_warn "DRY RUN completed - no actual changes were made"
    echo ""
    log_info "Run without --dry-run to perform actual upload and database insert"
fi

if [ $FAILED_COUNT -gt 0 ]; then
    log_warn "Some files failed to process. Check the logs above for details."
    exit 1
fi

log_success "All files processed successfully!"
echo ""
log_info "Webhook notifications sent to: $WEBHOOK_URL"
log_info "Config will be automatically updated by the webhook handler"
echo ""

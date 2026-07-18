#!/bin/bash
# MIRROR of /home/ubuntu/backup-scripts/backup_mysql_data_to_s3_skilltree.sh (2026-07-18)
# Credentials REDACTED at extraction time — not runnable as-is. See README.md.

# Configuration
DB_NAME="skilltree"
DB_USER="root"
DB_PASSWORD=REDACTED
DOCKER_CONTAINER_NAME="prod-database-skilltree"

# AWS S3 configuration
S3_BUCKET="{{BACKUP_BUCKET_SKILLTREE}}"
S3_PATH="backups/mysql"

# Backup directory
BACKUP_DIR="./skilltree"
mkdir -p $BACKUP_DIR

# Generate timestamp
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILENAME="backup_${DB_NAME}_${TIMESTAMP}.sql"
ZIPPED_BACKUP_FILENAME="${BACKUP_FILENAME}.gz"

# Log functions
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >&2
}

# Error handling
set -e

# Define error handler function
error_handler() {
    local line_no=$1
    local error_code=$2
    log_error "Error occurred in script at line: ${line_no}, with exit code: ${error_code}"
}

# Set the error trap
trap 'error_handler ${LINENO} $?' ERR

# Function to check if Docker container is running and MySQL is accessible
check_docker_container() {
    log "Checking Docker container status..."
    if ! docker ps | grep -q "$DOCKER_CONTAINER_NAME"; then
        log_error "Docker container '$DOCKER_CONTAINER_NAME' is not running"
        return 1
    fi

    # Test MySQL connection inside container
    if ! docker exec "$DOCKER_CONTAINER_NAME" mysqladmin \
        -u"$DB_USER" \
        -pREDACTED \
        ping --silent; then
        log_error "Cannot connect to MySQL inside container"
        return 1
    fi

    log "Docker container and MySQL connection verified"
    return 0
}

# Function to verify backup file
verify_backup() {
    local backup_file="$1"

    # Check if file exists and is not empty
    if [ ! -s "$backup_file" ]; then
        log_error "Backup file is empty or does not exist"
        return 1
    fi

    # For uncompressed backup, check if it's a valid MySQL dump
    if [[ $backup_file != *.gz ]]; then
        if ! grep -q "Dump completed" "$backup_file"; then
            log_error "Backup file does not contain valid MySQL dump"
            return 1
        fi
    fi

    # Get file size
    local file_size
    if [ "$(uname)" == "Darwin" ]; then
        file_size=$(stat -f%z "$backup_file")
    else
        file_size=$(stat -c%s "$backup_file")
    fi
    log "Backup size: $file_size bytes"

    # Check minimum expected size (1KB)
    if [ "$file_size" -lt 1024 ]; then
        log_error "Backup file suspiciously small (< 1KB)"
        return 1
    fi

    return 0
}

# Function to verify S3 upload
verify_s3_upload() {
    local s3_path="$1"
    local local_file="$2"

    # Get local file checksum
    local local_md5
    if [ "$(uname)" == "Darwin" ]; then
        local_md5=$(md5 -q "$local_file")
    else
        local_md5=$(md5sum "$local_file" | awk '{print $1}')
    fi

    # Get S3 file checksum
    local s3_md5
    s3_md5=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$s3_path" --query 'ETag' --output text | tr -d '"')

    if [ "$local_md5" = "$s3_md5" ]; then
        log "S3 upload verified successfully (checksums match)"
        return 0
    else
        log_error "S3 upload verification failed (checksums do not match)"
        return 1
    fi
}

# Main execution
main() {
    # Check Docker container
    if ! check_docker_container; then
        exit 1
    fi

    # Create backup
    log "Starting database backup..."
    if ! (docker exec \
        -t "$DOCKER_CONTAINER_NAME" \
        mysqldump \
        --user="$DB_USER" \
        --password=REDACTED \
        --single-transaction \
        --quick \
        --lock-tables=false \
        --add-drop-database \
        --add-drop-table \
        --databases "$DB_NAME") >"$BACKUP_DIR/$BACKUP_FILENAME" 2>"$BACKUP_DIR/mysql_dump_error.log"; then

        log_error "Database backup failed. Error log:"
        cat "$BACKUP_DIR/mysql_dump_error.log"
        exit 1
    fi

    # Verify uncompressed backup
    log "Verifying backup file..."
    if ! verify_backup "$BACKUP_DIR/$BACKUP_FILENAME"; then
        exit 1
    fi

    # Compress backup
    log "Compressing backup..."
    if ! gzip -f "$BACKUP_DIR/$BACKUP_FILENAME"; then
        log_error "Compression failed"
        exit 1
    fi

    # Verify compressed backup
    if ! verify_backup "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME"; then
        exit 1
    fi

    # Upload to S3
    log "Uploading to S3..."
    local s3_key="$S3_PATH/$ZIPPED_BACKUP_FILENAME"
    if ! aws s3 cp "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME" "s3://$S3_BUCKET/$s3_key"; then
        log_error "S3 upload failed"
        exit 1
    fi

    # Verify S3 upload
    log "Verifying S3 upload..."
    if ! verify_s3_upload "$s3_key" "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME"; then
        exit 1
    fi

    # Clean up local backup
    log "Cleaning up local backup..."
    rm -f "$BACKUP_DIR/$BACKUP_FILENAME" "$BACKUP_DIR/$ZIPPED_BACKUP_FILENAME" "$BACKUP_DIR/mysql_dump_error.log"

    log "Backup process completed successfully"
    return 0
}

# Execute main function
main

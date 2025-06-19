#!/bin/bash

# MySQL Configuration Script for Monitoring Agent
# Enables error logging and slow query logging for better monitoring

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "================================================================================"
echo "CONFIGURING MYSQL FOR MONITORING"
echo "================================================================================"

# Check if MySQL is installed and running
if ! systemctl is-active --quiet mysql; then
    echo "⚠ WARNING: MySQL service is not running"
    echo "Attempting to start MySQL..."
    if systemctl start mysql; then
        echo "✓ MySQL started successfully"
        sleep 2
    else
        echo "✗ ERROR: Could not start MySQL service"
        echo "Please ensure MySQL is properly installed and configured"
        exit 1
    fi
fi

# Load environment variables to get MySQL credentials
if [ -f "/opt/monitoring-agent/.env" ]; then
    export $(grep -v '^#' /opt/monitoring-agent/.env | xargs)
    echo "✓ Loaded MySQL credentials from monitoring agent configuration"
else
    echo "⚠ WARNING: Could not find /opt/monitoring-agent/.env"
    echo "Using default connection (root with no password)"
fi

# Test MySQL connection first
echo ""
echo "Testing MySQL connection..."
if [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ]; then
    MYSQL_CMD="mysql -u $MYSQL_USER -p$MYSQL_PASSWORD"
    echo "Using credentials: $MYSQL_USER@localhost"
elif [ -n "$MYSQL_USER" ]; then
    MYSQL_CMD="mysql -u $MYSQL_USER"
    echo "Using user: $MYSQL_USER (no password)"
else
    MYSQL_CMD="mysql -u root"
    echo "Using default: root (no password)"
fi

# Test connection
if ! $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✗ ERROR: Cannot connect to MySQL with provided credentials"
    echo "Please verify MySQL credentials in /opt/monitoring-agent/.env"
    exit 1
fi

echo "✓ MySQL connection successful"

# Backup current configuration
MYSQL_CONFIG="/etc/mysql/my.cnf"
BACKUP_FILE="/etc/mysql/my.cnf.backup.$(date +%Y%m%d_%H%M%S)"

echo ""
echo "Creating backup of MySQL configuration..."
cp "$MYSQL_CONFIG" "$BACKUP_FILE"
echo "✓ Backup created: $BACKUP_FILE"

# Check if our monitoring section already exists
if grep -q "# LiberrexMonitoringAgent MySQL Configuration" "$MYSQL_CONFIG"; then
    echo ""
    echo "⚠ Monitoring configuration already exists in my.cnf"
    echo "Skipping configuration to prevent duplicates"
    echo "If you need to reconfigure, remove the existing section manually"
    exit 0
fi

# Add monitoring configuration to the end of my.cnf
echo ""
echo "Adding monitoring configuration to $MYSQL_CONFIG..."

cat >> "$MYSQL_CONFIG" << 'EOF'

###############################################################################
# LiberrexMonitoringAgent MySQL Configuration
# Added automatically by configure_mysql.sh
###############################################################################

[mysqld]
# Error logging - essential for monitoring
log_error = /var/log/mysql/error.log

# Slow query logging - helps identify performance issues
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2

# Performance schema - enables detailed performance monitoring
performance_schema = ON

# General logging (optional - can generate large logs)
# general_log = 1
# general_log_file = /var/log/mysql/mysql.log

###############################################################################
# End of LiberrexMonitoringAgent Configuration
###############################################################################
EOF

echo "✓ Monitoring configuration added to my.cnf"

# Create MySQL log directory if it doesn't exist
MYSQL_LOG_DIR="/var/log/mysql"
if [ ! -d "$MYSQL_LOG_DIR" ]; then
    echo ""
    echo "Creating MySQL log directory..."
    mkdir -p "$MYSQL_LOG_DIR"
    chown mysql:mysql "$MYSQL_LOG_DIR"
    chmod 750 "$MYSQL_LOG_DIR"
    echo "✓ Created $MYSQL_LOG_DIR with proper permissions"
else
    echo "✓ MySQL log directory already exists"
fi

# Test MySQL configuration
echo ""
echo "Testing MySQL configuration..."
if mysqld --help --verbose >/dev/null 2>&1; then
    echo "✓ MySQL configuration test passed"
else
    echo "✗ ERROR: MySQL configuration test failed"
    echo "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$MYSQL_CONFIG"
    echo "✓ Configuration restored from backup"
    exit 1
fi

# Restart MySQL to apply changes
echo ""
echo "Restarting MySQL to apply configuration changes..."
if systemctl restart mysql; then
    echo "✓ MySQL restarted successfully"
    
    # Wait for MySQL to fully start
    sleep 3
    
    # Verify MySQL is running
    if systemctl is-active --quiet mysql; then
        echo "✓ MySQL is running properly"
        
        # Test connection again after restart
        if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✓ MySQL connection still working after restart"
        else
            echo "⚠ WARNING: MySQL connection failed after restart"
        fi
        
        # Check if logging is actually enabled
        echo ""
        echo "Verifying logging configuration..."
        
        # Check slow query log
        SLOW_LOG_STATUS=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'slow_query_log';" 2>/dev/null | grep slow_query_log | awk '{print $2}')
        if [ "$SLOW_LOG_STATUS" = "ON" ]; then
            echo "✓ Slow query logging: ENABLED"
        else
            echo "⚠ Slow query logging: DISABLED"
        fi
        
        # Check error log
        ERROR_LOG_FILE=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'log_error';" 2>/dev/null | grep log_error | awk '{print $2}')
        if [ -n "$ERROR_LOG_FILE" ]; then
            echo "✓ Error logging: ENABLED ($ERROR_LOG_FILE)"
        else
            echo "⚠ Error logging: NOT CONFIGURED"
        fi
        
        # Check performance schema
        PERF_SCHEMA_STATUS=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'performance_schema';" 2>/dev/null | grep performance_schema | awk '{print $2}')
        if [ "$PERF_SCHEMA_STATUS" = "ON" ]; then
            echo "✓ Performance schema: ENABLED"
        else
            echo "⚠ Performance schema: DISABLED"
        fi
        
    else
        echo "✗ ERROR: MySQL failed to start after configuration changes"
        echo "Restoring backup configuration..."
        cp "$BACKUP_FILE" "$MYSQL_CONFIG"
        systemctl restart mysql
        exit 1
    fi
else
    echo "✗ ERROR: Failed to restart MySQL"
    echo "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$MYSQL_CONFIG"
    exit 1
fi

echo ""
echo "================================================================================"
echo "MYSQL CONFIGURATION COMPLETED SUCCESSFULLY"
echo "================================================================================"
echo ""
echo "Configuration changes made:"
echo "✓ Error logging enabled: /var/log/mysql/error.log"
echo "✓ Slow query logging enabled: /var/log/mysql/mysql-slow.log"
echo "✓ Slow query threshold: 2 seconds"
echo "✓ Performance schema enabled for detailed monitoring"
echo ""
echo "Log files location: $MYSQL_LOG_DIR"
echo "Configuration backup: $BACKUP_FILE"
echo ""
echo "The monitoring agent can now collect enhanced MySQL metrics including:"
echo "- Error log analysis"
echo "- Slow query detection and analysis" 
echo "- Performance schema metrics"
echo "- Enhanced connection and resource monitoring"

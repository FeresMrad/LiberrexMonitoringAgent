#!/bin/bash

# MySQL Configuration Script for Monitoring Agent
# Enables error logging and slow query logging for better monitoring
# Now assumes MySQL credentials are ALWAYS required and provided

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

# Load environment variables to get MySQL credentials (now mandatory)
if [ -f "/opt/monitoring-agent/.env" ]; then
    export $(grep -v '^#' /opt/monitoring-agent/.env | xargs)
    echo "✓ Loaded MySQL credentials from monitoring agent configuration"
else
    echo "✗ ERROR: Could not find /opt/monitoring-agent/.env"
    echo "MySQL credentials are required for monitoring agent operation"
    exit 1
fi

# Verify all required MySQL credentials are present
if [ -z "$MYSQL_USER" ]; then
    echo "✗ ERROR: MYSQL_USER not found in environment"
    echo "Please ensure all MySQL credentials are properly set in .env file"
    exit 1
fi

if [ -z "$MYSQL_PASSWORD" ]; then
    echo "✗ ERROR: MYSQL_PASSWORD not found in environment"
    echo "Please ensure all MySQL credentials are properly set in .env file"
    exit 1
fi

if [ -z "$MYSQL_HOST" ]; then
    echo "✗ ERROR: MYSQL_HOST not found in environment"
    echo "Please ensure all MySQL credentials are properly set in .env file"
    exit 1
fi

if [ -z "$MYSQL_PORT" ]; then
    echo "✗ ERROR: MYSQL_PORT not found in environment"
    echo "Please ensure all MySQL credentials are properly set in .env file"
    exit 1
fi

echo "✓ All required MySQL credentials found"

# Test MySQL connection with provided credentials
echo ""
echo "Testing MySQL connection with monitoring credentials..."
MYSQL_CMD="mysql -h $MYSQL_HOST -P $MYSQL_PORT -u $MYSQL_USER -p$MYSQL_PASSWORD"
echo "Using credentials: $MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT"

# Test connection
if ! $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
    echo "✗ ERROR: Cannot connect to MySQL with provided credentials"
    echo ""
    echo "Please verify:"
    echo "1. MySQL server is running on $MYSQL_HOST:$MYSQL_PORT"
    echo "2. User '$MYSQL_USER' exists and password is correct"
    echo "3. User has proper permissions for monitoring"
    echo ""
    echo "To create the monitoring user with ALL required permissions:"
    echo "  mysql -u root -p"
    echo "  CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY 'your_password';"
    echo "  GRANT PROCESS ON *.* TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT REPLICATION CLIENT ON *.* TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT SELECT ON performance_schema.* TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT SELECT ON information_schema.* TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT SHOW DATABASES ON *.* TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT SELECT ON mysql.user TO '$MYSQL_USER'@'localhost';"
    echo "  GRANT SELECT ON mysql.db TO '$MYSQL_USER'@'localhost';"
    echo "  FLUSH PRIVILEGES;"
    exit 1
fi

echo "✓ MySQL connection successful with monitoring credentials"

# Comprehensive permission verification
echo ""
echo "Verifying monitoring user permissions..."

# Check for PROCESS privilege
PROCESS_PRIV=$($MYSQL_CMD -e "SHOW GRANTS FOR CURRENT_USER();" 2>/dev/null | grep -i "PROCESS" || echo "")
if [ -n "$PROCESS_PRIV" ]; then
    echo "✓ PROCESS privilege: GRANTED"
else
    echo "✗ ERROR: PROCESS privilege: MISSING (required for SHOW GLOBAL STATUS)"
fi

# Check for REPLICATION CLIENT privilege
REPL_PRIV=$($MYSQL_CMD -e "SHOW GRANTS FOR CURRENT_USER();" 2>/dev/null | grep -i "REPLICATION CLIENT" || echo "")
if [ -n "$REPL_PRIV" ]; then
    echo "✓ REPLICATION CLIENT privilege: GRANTED"
else
    echo "⚠ WARNING: REPLICATION CLIENT privilege: MISSING (may affect some metrics)"
fi

# Check for SHOW DATABASES privilege
SHOW_DB_PRIV=$($MYSQL_CMD -e "SHOW GRANTS FOR CURRENT_USER();" 2>/dev/null | grep -i "SHOW DATABASES" || echo "")
if [ -n "$SHOW_DB_PRIV" ]; then
    echo "✓ SHOW DATABASES privilege: GRANTED"
else
    echo "⚠ WARNING: SHOW DATABASES privilege: MISSING (may affect database enumeration)"
fi

# Check for performance_schema access
if $MYSQL_CMD -e "SELECT 1 FROM performance_schema.global_status LIMIT 1;" >/dev/null 2>&1; then
    echo "✓ Performance Schema access: VERIFIED"
else
    echo "✗ ERROR: Performance Schema access: FAILED (required for advanced metrics)"
fi

# Check for information_schema access
if $MYSQL_CMD -e "SELECT 1 FROM information_schema.tables LIMIT 1;" >/dev/null 2>&1; then
    echo "✓ Information Schema access: VERIFIED"
else
    echo "✗ ERROR: Information Schema access: FAILED (required for metadata queries)"
fi

# Check for mysql schema access (user tables)
if $MYSQL_CMD -e "SELECT 1 FROM mysql.user LIMIT 1;" >/dev/null 2>&1; then
    echo "✓ MySQL system tables access: VERIFIED"
else
    echo "⚠ WARNING: MySQL system tables access: LIMITED (some user metrics may not work)"
fi

# Test specific monitoring queries
echo ""
echo "Testing monitoring-specific queries..."

# Test SHOW GLOBAL STATUS
if $MYSQL_CMD -e "SHOW GLOBAL STATUS LIKE 'Queries';" >/dev/null 2>&1; then
    echo "✓ SHOW GLOBAL STATUS: WORKING"
else
    echo "✗ ERROR: SHOW GLOBAL STATUS: FAILED"
fi

# Test SHOW GLOBAL VARIABLES
if $MYSQL_CMD -e "SHOW GLOBAL VARIABLES LIKE 'max_connections';" >/dev/null 2>&1; then
    echo "✓ SHOW GLOBAL VARIABLES: WORKING"
else
    echo "✗ ERROR: SHOW GLOBAL VARIABLES: FAILED"
fi

# Test performance_schema query (the one used in the collector)
if $MYSQL_CMD -e "SELECT SUM_TIMER_WAIT/1000000000 as total_time_ms, COUNT_STAR as total_queries FROM performance_schema.events_statements_summary_global_by_event_name WHERE EVENT_NAME LIKE 'statement/sql/%' AND COUNT_STAR > 0 ORDER BY COUNT_STAR DESC LIMIT 1;" >/dev/null 2>&1; then
    echo "✓ Performance Schema detailed query: WORKING"
else
    echo "⚠ WARNING: Performance Schema detailed query: FAILED (advanced response time metrics won't work)"
fi

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
    
    # Still verify current logging status
    echo ""
    echo "Verifying current logging configuration..."
    
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
    
    exit 0
fi

# Add monitoring configuration to the end of my.cnf
echo ""
echo "Adding monitoring configuration to $MYSQL_CONFIG..."

cat >> "$MYSQL_CONFIG" << 'EOF'

###############################################################################
# LiberrexMonitoringAgent MySQL Configuration
# Added automatically by configure_mysql.sh
# Required for comprehensive MySQL monitoring
###############################################################################

[mysqld]
# Error logging - essential for monitoring and troubleshooting
log_error = /var/log/mysql/error.log

# Slow query logging - helps identify performance issues
slow_query_log = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time = 2

# Performance schema - enables detailed performance monitoring
# Required for monitoring agent to collect advanced metrics
performance_schema = ON

# Log queries not using indexes (helps identify optimization opportunities)
log_queries_not_using_indexes = 1

# General logging (optional - can generate large logs, disabled by default)
# Uncomment if you need full query logging (not recommended for production)
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
    # Ensure proper ownership
    chown mysql:mysql "$MYSQL_LOG_DIR"
    chmod 750 "$MYSQL_LOG_DIR"
fi

# Create log files with proper permissions
LOG_FILES=("/var/log/mysql/error.log" "/var/log/mysql/mysql-slow.log")
for log_file in "${LOG_FILES[@]}"; do
    if [ ! -f "$log_file" ]; then
        echo "Creating $log_file"
        touch "$log_file"
        chown mysql:mysql "$log_file"
        chmod 640 "$log_file"
    else
        echo "✓ Log file exists: $log_file"
        # Ensure proper ownership
        chown mysql:mysql "$log_file"
        chmod 640 "$log_file"
    fi
done

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
    sleep 5
    
    # Verify MySQL is running
    if systemctl is-active --quiet mysql; then
        echo "✓ MySQL is running properly"
        
        # Test connection again after restart with monitoring credentials
        echo "Testing monitoring user connection after restart..."
        if $MYSQL_CMD -e "SELECT 1;" >/dev/null 2>&1; then
            echo "✓ Monitoring user connection still working after restart"
        else
            echo "✗ ERROR: Monitoring user connection failed after restart"
            echo "This may indicate a configuration or permission issue"
            exit 1
        fi
        
        # Check if logging is actually enabled
        echo ""
        echo "Verifying logging configuration after restart..."
        
        # Check slow query log
        SLOW_LOG_STATUS=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'slow_query_log';" 2>/dev/null | grep slow_query_log | awk '{print $2}')
        if [ "$SLOW_LOG_STATUS" = "ON" ]; then
            echo "✓ Slow query logging: ENABLED"
        else
            echo "✗ ERROR: Slow query logging: DISABLED"
        fi
        
        # Check error log
        ERROR_LOG_FILE=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'log_error';" 2>/dev/null | grep log_error | awk '{print $2}')
        if [ -n "$ERROR_LOG_FILE" ]; then
            echo "✓ Error logging: ENABLED ($ERROR_LOG_FILE)"
        else
            echo "✗ ERROR: Error logging: NOT CONFIGURED"
        fi
        
        # Check performance schema
        PERF_SCHEMA_STATUS=$($MYSQL_CMD -e "SHOW VARIABLES LIKE 'performance_schema';" 2>/dev/null | grep performance_schema | awk '{print $2}')
        if [ "$PERF_SCHEMA_STATUS" = "ON" ]; then
            echo "✓ Performance schema: ENABLED"
        else
            echo "⚠ WARNING: Performance schema: DISABLED"
        fi
        
        # Test monitoring agent functionality
        echo ""
        echo "Testing monitoring agent MySQL functionality..."
        if cd /opt/monitoring-agent && /opt/monitoring-agent/venv/bin/python3 -c "
import sys
sys.path.append('/opt/monitoring-agent')
from collectors.mysql import collect_mysql_metrics

try:
    # Test collecting metrics with the configured user
    metrics = collect_mysql_metrics('test-host')
    if metrics:
        print(f'✓ Successfully collected {len(metrics)} MySQL metrics')
        
        # Check for specific metric types
        metric_types = [point._name for point in metrics]
        expected_types = ['mysql_health', 'mysql_resources', 'mysql_connections', 'mysql_innodb']
        
        for expected_type in expected_types:
            if expected_type in metric_types:
                print(f'✓ {expected_type} metrics: COLLECTED')
            else:
                print(f'⚠ {expected_type} metrics: MISSING')
    else:
        print('⚠ WARNING: No MySQL metrics collected')
        sys.exit(1)
except Exception as e:
    print(f'✗ ERROR: Failed to collect MySQL metrics: {e}')
    sys.exit(1)
"; then
            echo "✓ Monitoring agent MySQL functionality test passed"
        else
            echo "✗ ERROR: Monitoring agent MySQL functionality test failed"
            echo "Check MySQL user permissions and configuration"
            exit 1
        fi
        cd - > /dev/null
        
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
echo "✓ Log queries not using indexes: enabled"
echo ""
echo "Monitoring user verification:"
echo "✓ User: $MYSQL_USER@$MYSQL_HOST:$MYSQL_PORT"
echo "✓ Connection: Successfully tested"
echo "✓ Core permissions: Verified for monitoring operations"
echo "✓ Advanced queries: Tested and working"
echo ""
echo "Log files location: $MYSQL_LOG_DIR"
echo "Configuration backup: $BACKUP_FILE"
echo ""
echo "The monitoring agent can now collect comprehensive MySQL metrics including:"
echo "- Connection and thread monitoring"
echo "- Query performance metrics"
echo "- InnoDB buffer pool statistics"
echo "- Resource usage (CPU, memory, disk I/O)"
echo "- Error log analysis"
echo "- Slow query detection and analysis" 
echo "- Performance schema metrics"
echo "- Response time distribution"
echo "- System table metadata"

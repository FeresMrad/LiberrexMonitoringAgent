#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "✗ ERROR: .env file not found"
    echo ""
    echo "Please create a .env file based on .env.template:"
    echo "1. Copy .env.template to .env: cp .env.template .env"
    echo "2. Edit .env and fill in your actual values"
    echo "3. Run install.sh again"
    echo ""
    echo "Required variables in .env:"
    echo "- INFLUXDB_URL"
    echo "- INFLUXDB_TOKEN"
    echo "- INFLUXDB_ORG"
    echo "- INFLUXDB_BUCKET"
    echo "- REMOTE_LOG_SERVER"
    echo "- MYSQL_HOST (for MySQL monitoring)"
    echo "- MYSQL_PORT (for MySQL monitoring)"
    echo "- MYSQL_USER (for MySQL monitoring)"
    echo "- MYSQL_PASSWORD (for MySQL monitoring)"
    exit 1
fi

echo "Found .env file, proceeding with installation..."

# Function to validate configuration using environment variables
validate_config() {
    echo "Validating configuration from .env file..."
    
    # Load environment variables
    export $(grep -v '^#' .env | xargs)
    
    # Check required variables
    if [ -z "$INFLUXDB_URL" ]; then
        echo "✗ ERROR: INFLUXDB_URL is required in .env file"
        exit 1
    fi
    
    if [ -z "$INFLUXDB_TOKEN" ]; then
        echo "✗ ERROR: INFLUXDB_TOKEN is required in .env file"
        exit 1
    fi
    
    if [ -z "$INFLUXDB_ORG" ]; then
        echo "✗ ERROR: INFLUXDB_ORG is required in .env file"
        exit 1
    fi
    
    if [ -z "$INFLUXDB_BUCKET" ]; then
        echo "✗ ERROR: INFLUXDB_BUCKET is required in .env file"
        exit 1
    fi
    
    if [ -z "$REMOTE_LOG_SERVER" ]; then
        echo "✗ ERROR: REMOTE_LOG_SERVER is required in .env file"
        exit 1
    fi
    
    # Check MySQL configuration (credentials always required if you want MySQL monitoring)
    # The MYSQL_ENABLED flag is now in config.py, so we check if credentials are provided
    if [ -n "$MYSQL_HOST" ] && [ -n "$MYSQL_PORT" ] && [ -n "$MYSQL_USER" ] && [ -n "$MYSQL_PASSWORD" ]; then
        echo "✓ MySQL credentials provided - MySQL monitoring will be enabled"
        MYSQL_CONFIGURED=true
    else
        echo "⚠ NOTE: MySQL credentials not provided - MySQL monitoring will be disabled"
        echo "  To enable MySQL monitoring, add these variables to .env:"
        echo "  - MYSQL_HOST"
        echo "  - MYSQL_PORT" 
        echo "  - MYSQL_USER"
        echo "  - MYSQL_PASSWORD"
        MYSQL_CONFIGURED=false
    fi
    
    echo "✓ Configuration validation passed"
    return 0
}

# Validate configuration before proceeding
validate_config

# Update package lists
apt update

# Install prerequisites
apt install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential \
    mysql-client

# Create the agent directory and subdirectories
mkdir -p /opt/monitoring-agent/collectors

# Create a virtual environment
python3 -m venv /opt/monitoring-agent/venv

# Activate virtual environment and install Python packages
/opt/monitoring-agent/venv/bin/pip install psutil requests influxdb-client uuid mysql-connector-python python-dotenv

# Copy agent files
echo "Copying agent files..."
cp agent.py config.py agent_id.py .env /opt/monitoring-agent/
cp collectors/__init__.py collectors/system.py collectors/ssh.py collectors/apache.py collectors/mysql.py /opt/monitoring-agent/collectors/

# Create empty __init__.py if not copied
touch /opt/monitoring-agent/collectors/__init__.py

# Set correct permissions
chmod 755 /opt/monitoring-agent/agent.py
chmod 600 /opt/monitoring-agent/.env  # Restrict access to environment file

# Generate or read agent-id for rsyslog configuration
AGENT_ID_FILE="/opt/monitoring-agent/agent-id"
if [ -f "$AGENT_ID_FILE" ]; then
    AGENT_ID=$(cat "$AGENT_ID_FILE")
    echo "Using existing agent-id: $AGENT_ID"
else
    # Generate a new UUID
    AGENT_ID=$(python3 -c 'import uuid; print(str(uuid.uuid4()))')
    echo "$AGENT_ID" > "$AGENT_ID_FILE"
    echo "Generated new agent-id: $AGENT_ID"
fi

# Test MySQL connection before proceeding (only if MySQL credentials are provided)
if [ "$MYSQL_CONFIGURED" = "true" ]; then
    echo ""
    echo "Testing MySQL connection..."
    if cd /opt/monitoring-agent && /opt/monitoring-agent/venv/bin/python3 -c "
import sys
from config import MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DATABASE, MYSQL_TIMEOUT
import mysql.connector

try:
    connection = mysql.connector.connect(
        host=MYSQL_HOST,
        port=MYSQL_PORT,
        user=MYSQL_USER,
        password=MYSQL_PASSWORD,
        database=MYSQL_DATABASE,
        connection_timeout=MYSQL_TIMEOUT
    )
    connection.close()
    print('MySQL connection successful')
except Exception as e:
    print(f'MySQL connection failed: {e}')
    sys.exit(1)
"; then
        echo "✓ MySQL connection test successful"
    else
        echo "✗ ERROR: MySQL connection test failed"
        echo ""
        echo "Please verify:"
        echo "1. MySQL server is running"
        echo "2. Credentials in .env file are correct"
        echo "3. Monitoring user exists and has proper permissions:"
        echo "   mysql -u root -p"
        echo "   CREATE USER '$MYSQL_USER'@'localhost' IDENTIFIED BY 'your_password';"
        echo "   GRANT PROCESS, REPLICATION CLIENT ON *.* TO '$MYSQL_USER'@'localhost';"
        echo "   GRANT SELECT ON performance_schema.* TO '$MYSQL_USER'@'localhost';"
        echo "   FLUSH PRIVILEGES;"
        exit 1
    fi
    cd - > /dev/null
else
    echo "⚠ NOTE: Skipping MySQL connection test (MySQL credentials not provided)"
fi

# Create systemd service file
cat > /etc/systemd/system/monitoring-agent.service << EOL
[Unit]
Description=System Monitoring Agent
After=network.target mysql.service

[Service]
ExecStart=/opt/monitoring-agent/venv/bin/python /opt/monitoring-agent/agent.py
WorkingDirectory=/opt/monitoring-agent
Restart=always
Environment=PATH=/opt/monitoring-agent/venv/bin

[Install]
WantedBy=multi-user.target
EOL

# Configure Apache FIRST (before rsyslog) since rsyslog will forward the modified logs
APACHE_SCRIPT="./configure_apache.sh"
if [ -f "$APACHE_SCRIPT" ]; then
    echo ""
    echo "================================================================================"
    echo "CONFIGURING APACHE (Step 1/4)"
    echo "================================================================================"
    
    # Make sure the script is executable
    chmod +x "$APACHE_SCRIPT"
    
    # Run the Apache configuration script
    if bash "$APACHE_SCRIPT"; then
        echo "✓ Apache configuration completed successfully"
        APACHE_STATUS="configured"
    else
        echo "⚠ WARNING: Apache configuration had issues, but continuing with installation"
        APACHE_STATUS="configuration issues"
    fi
else
    echo "⚠ NOTE: configure_apache.sh not found - skipping Apache optimization"
    APACHE_STATUS="not configured"
fi

# Configure rsyslog using separate script (AFTER Apache config)
RSYSLOG_SCRIPT="./configure_rsyslog.sh"
if [ -f "$RSYSLOG_SCRIPT" ]; then
    echo ""
    echo "================================================================================"
    echo "CONFIGURING RSYSLOG (Step 2/4)"
    echo "================================================================================"
    
    # Make sure the script is executable
    chmod +x "$RSYSLOG_SCRIPT"
    
    # Export REMOTE_LOG_SERVER for the rsyslog script
    export REMOTE_LOG_SERVER
    
    # Run the rsyslog configuration script with agent ID
    if bash "$RSYSLOG_SCRIPT" "$AGENT_ID"; then
        echo "✓ Rsyslog configuration completed successfully"
        RSYSLOG_STATUS="configured"
    else
        echo "✗ ERROR: Rsyslog configuration failed"
        echo "Manual setup required - check configure_rsyslog.sh"
        exit 1
    fi
else
    echo "⚠ WARNING: configure_rsyslog.sh not found - using basic rsyslog setup"
    
    # Fallback to basic configuration
    echo "\$LocalHostName $AGENT_ID" >> /etc/rsyslog.conf
    systemctl restart rsyslog
    RSYSLOG_STATUS="basic setup"
fi

FAIL2BAN_SCRIPT="./configure_fail2ban.sh"
if [ -f "$FAIL2BAN_SCRIPT" ]; then
    echo ""
    echo "================================================================================"
    echo "CONFIGURING FAIL2BAN SECURITY (Step 3/4)"
    echo "================================================================================"
    
    # Make sure the script is executable
    chmod +x "$FAIL2BAN_SCRIPT"
    
    # Run the fail2ban configuration script
    if bash "$FAIL2BAN_SCRIPT"; then
        echo "✓ Fail2ban security configuration completed successfully"
        FAIL2BAN_STATUS="configured"
    else
        echo "⚠ WARNING: Fail2ban configuration had issues, but continuing with installation"
        FAIL2BAN_STATUS="configuration issues"
    fi
else
    echo ""
    echo "================================================================================"
    echo "CONFIGURING FAIL2BAN SECURITY (Step 3/4)"
    echo "================================================================================"
    echo "⚠ NOTE: configure_fail2ban.sh not found - skipping security configuration"
    echo "To enable security features, place configure_fail2ban.sh in the same directory"
    FAIL2BAN_STATUS="script not found"
fi

echo ""
echo "================================================================================"
echo "STARTING MONITORING AGENT (Step 4/4)"
echo "================================================================================"

# Reload systemd to recognize the new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable monitoring-agent

# Start the service
systemctl start monitoring-agent

# Verify service started successfully
sleep 2
if systemctl is-active --quiet monitoring-agent; then
    echo ""
    echo "================================================================================"
    echo "INSTALLATION COMPLETED SUCCESSFULLY"
    echo "================================================================================"
    echo "Monitoring agent installed and started successfully with agent ID: $AGENT_ID"
    echo ""
    echo "Monitoring configuration summary:"
    echo "- System metrics (CPU, Memory, Disk, Network)"
    echo "- SSH authentication events from /var/log/auth.log"
    echo "- Apache access logs from /var/log/apache2/access.log"
    
    if [ "$MYSQL_CONFIGURED" = "true" ]; then
        echo "- MySQL performance and health metrics"
        echo "- MySQL User: $MYSQL_USER"
        echo "- Connection: ✓ Verified"
    else
        echo "- MySQL monitoring: Disabled (no credentials provided)"
    fi
    
    echo "- Server-status requests filtered out"
    echo "- All logs forwarded to $REMOTE_LOG_SERVER without local storage"
    echo "- Queue size limited to 50MB to prevent disk issues"
    echo "- Using unified monitoring.conf configuration file"
    echo ""
    echo "Fail2ban security configuration:"
    echo "- SSH brute force protection"
    echo "- Apache error log monitoring"
    echo "- Apache access log monitoring with custom filters"
    echo "- Recidive jail for repeat offenders"
    echo "- All configurations safely merged with existing settings"
    echo ""
    echo "Services status:"
    echo "- Monitoring Agent: $(systemctl is-active monitoring-agent)"
    echo "- Fail2ban: $(systemctl is-active fail2ban)"
    echo "- Rsyslog: $(systemctl is-active rsyslog)"
    echo "- MySQL: $(systemctl is-active mysql)"
else
    echo "ERROR: Monitoring agent failed to start. Check logs with: journalctl -u monitoring-agent"
    exit 1
fi

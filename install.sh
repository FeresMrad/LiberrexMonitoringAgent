#!/bin/bash

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Update package lists
apt update

# Install prerequisites
apt install -y \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    build-essential

# Create the agent directory and subdirectories
mkdir -p /opt/monitoring-agent/collectors

# Create a virtual environment
python3 -m venv /opt/monitoring-agent/venv

# Activate virtual environment and install Python packages
/opt/monitoring-agent/venv/bin/pip install psutil requests influxdb-client uuid

# Copy agent files
echo "Copying agent files..."
cp agent.py config.py agent_id.py /opt/monitoring-agent/
cp collectors/__init__.py collectors/system.py collectors/ssh.py collectors/apache.py /opt/monitoring-agent/collectors/

# Create empty __init__.py if not copied
touch /opt/monitoring-agent/collectors/__init__.py

# Set correct permissions
chmod 755 /opt/monitoring-agent/agent.py

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

# Create systemd service file
cat > /etc/systemd/system/monitoring-agent.service << EOL
[Unit]
Description=System Monitoring Agent
After=network.target

[Service]
ExecStart=/opt/monitoring-agent/venv/bin/python /opt/monitoring-agent/agent.py
WorkingDirectory=/opt/monitoring-agent
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# Configure rsyslog with proper settings to prevent storage issues
echo "# Configuring rsyslog for monitoring agent"

# Remove any existing LocalHostName lines and forwarding rules
if grep -q "^\$LocalHostName" /etc/rsyslog.conf; then
    sed -i '/^\$LocalHostName/d' /etc/rsyslog.conf
    echo "Removed existing LocalHostName configuration"
fi

# Remove any existing forwarding rules to prevent duplicates
if grep -q "@@82\.165\.230\.7:29514" /etc/rsyslog.conf; then
    sed -i '/@@82\.165\.230\.7:29514/d' /etc/rsyslog.conf
    echo "Removed existing forwarding configuration"
fi

# Remove any wildcard forwarding rules that send all logs
if grep -q "^\*\.\*" /etc/rsyslog.conf; then
    sed -i '/^\*\.\*/d' /etc/rsyslog.conf
    echo "Removed wildcard forwarding configuration"
fi

# Add LocalHostName configuration
echo "\$LocalHostName $AGENT_ID" >> /etc/rsyslog.conf
echo "Added LocalHostName configuration to rsyslog"

# Create SSH-specific rsyslog configuration
echo "# Setting up SSH logging configuration"
cat > /etc/rsyslog.d/ssh-monitoring.conf << EOL
###############################################################################
# SSH Monitoring Configuration
# Forwards only SSH authentication events
###############################################################################

# Forward SSH daemon logs (authentication events)
if (\$programname == 'sshd') then {
    @@82.165.230.7:29514
    stop
}
EOL

echo "Created SSH monitoring rsyslog configuration"

# Create Apache-specific rsyslog configuration  
echo "# Setting up Apache logging configuration"
cat > /etc/rsyslog.d/apache-monitoring.conf << EOL
###############################################################################
# Apache Monitoring Configuration  
# Monitors Apache access logs and forwards selectively
###############################################################################

# Load imfile module for file monitoring
module(load="imfile" PollingInterval="10")

# Monitor Apache's main access log
input(type="imfile"
      File="/var/log/apache2/access.log"
      Tag="apache-access:"
      Facility="local2"
      Severity="info"
      PersistStateInterval="200"
)

# Filter out monitoring and internal requests
if (\$programname == 'apache-access' and (
    (\$msg contains '127.0.0.1' and \$msg contains 'GET /server-status?auto') or
    (\$msg contains '"OPTIONS * HTTP/1.0"' and \$msg contains 'internal dummy connection') or
    (\$msg contains '::1' and \$msg contains '"OPTIONS * HTTP/1.0"') or
    (\$msg contains '127.0.0.1' and \$msg contains '"OPTIONS * HTTP/1.0"')
)) then {
    stop
}

# Forward Apache access logs and stop local processing
if (\$programname == 'apache-access') then {
    @@82.165.230.7:29514
    stop
}

###############################################################################
# Error handling and queue configuration
###############################################################################
# Prevent infinite retries and disk space issues
\$ActionResumeRetryCount 3
\$ActionQueueMaxDiskSpace 50M
\$ActionQueueType LinkedList
\$ActionQueueFileName apache_queue
\$ActionQueueSaveOnShutdown on

# Drop messages if remote server is unreachable for too long
\$ActionExecOnlyWhenPreviousIsSuspended on
EOL

echo "Created Apache monitoring rsyslog configuration"

# Modify Apache logging format to include response time (%D) if Apache is installed
if [ -f "/etc/apache2/apache2.conf" ]; then
    echo "# Modifying Apache logging format to include response time (%D)"
    
    # Check if LogFormat lines already include %D
    APACHE_MODIFIED=0
    
    # Update vhost_combined format
    if grep -q 'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined' /etc/apache2/apache2.conf; then
        sed -i 's/LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined/LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined/' /etc/apache2/apache2.conf
        APACHE_MODIFIED=1
    fi
    
    # Update combined format
    if grep -q 'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined' /etc/apache2/apache2.conf; then
        sed -i 's/LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined/LogFormat "%h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined/' /etc/apache2/apache2.conf
        APACHE_MODIFIED=1
    fi
    
    # Update common format
    if grep -q 'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common' /etc/apache2/apache2.conf; then
        sed -i 's/LogFormat "%h %l %u %t \\"%r\\" %>s %O" common/LogFormat "%h %l %u %t \\"%r\\" %>s %O %D" common/' /etc/apache2/apache2.conf
        APACHE_MODIFIED=1
    fi
    
    # Restart Apache if modified
    if [ $APACHE_MODIFIED -eq 1 ]; then
        echo "Apache logging formats updated, restarting Apache service"
        systemctl restart apache2
    else
        echo "Apache logging formats already include response time or custom format is used"
    fi
else
    echo "Apache configuration not found, skipping LogFormat modifications"
fi

# Test rsyslog configuration before applying
rsyslogd -N1 -f /etc/rsyslog.conf
if [ $? -ne 0 ]; then
    echo "ERROR: Invalid rsyslog configuration. Please check the config files."
    exit 1
fi

# Restart rsyslog service to apply all changes
systemctl restart rsyslog
if [ $? -eq 0 ]; then
    echo "Rsyslog configured and restarted successfully"
else
    echo "ERROR: Failed to restart rsyslog. Check configuration."
    exit 1
fi

# Reload systemd to recognize the new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable monitoring-agent

# Start the service
systemctl start monitoring-agent

# Verify service started successfully
sleep 2
if systemctl is-active --quiet monitoring-agent; then
    echo "Monitoring agent installed and started successfully with agent ID: $AGENT_ID"
    echo ""
    echo "Monitoring configuration summary:"
    echo "- SSH authentication events from /var/log/auth.log"
    echo "- Apache access logs from /var/log/apache2/access.log"
    echo "- Server-status requests filtered out"
    echo "- All logs forwarded to 82.165.230.7:29514 without local storage"
    echo "- Queue size limited to 50MB to prevent disk issues"
else
    echo "ERROR: Monitoring agent failed to start. Check logs with: journalctl -u monitoring-agent"
    exit 1
fi

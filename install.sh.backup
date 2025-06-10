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

# Configure Apache FIRST (before rsyslog) since rsyslog will forward the modified logs
APACHE_SCRIPT="./configure_apache.sh"
if [ -f "$APACHE_SCRIPT" ]; then
    echo ""
    echo "================================================================================"
    echo "CONFIGURING APACHE (Step 1/3)"
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
    echo "CONFIGURING RSYSLOG (Step 2/3)"
    echo "================================================================================"
    
    # Make sure the script is executable
    chmod +x "$RSYSLOG_SCRIPT"
    
    # Run the rsyslog configuration script with agent ID
    if bash "$RSYSLOG_SCRIPT" "$AGENT_ID"; then
        echo "✓ Rsyslog configuration completed successfully"
        RSYSLOG_STATUS="configured"
    else
        echo "✗ ERROR: Rsyslog configuration failed"
        echo "Manual setup required - check rsyslog configuration"
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
    echo "CONFIGURING FAIL2BAN SECURITY (Step 3/3)"
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
    echo "CONFIGURING FAIL2BAN SECURITY (Step 3/3)"
    echo "================================================================================"
    echo "⚠ NOTE: configure_fail2ban.sh not found - skipping security configuration"
    echo "To enable security features, place configure_fail2ban.sh in the same directory"
    FAIL2BAN_STATUS="script not found"
fi

# Reload systemd to recognize the new service
systemctl daemon-reload

# Enable the service to start on boot
systemctl enable monitoring-agent

# Start the service
systemctl start monitoring-agent

# Verify service started successfully
sleep 2

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
    echo "- SSH authentication events from /var/log/auth.log"
    echo "- Apache access logs from /var/log/apache2/access.log"
    echo "- Server-status requests filtered out"
    echo "- All logs forwarded to 82.165.230.7:29514 without local storage"
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
else
    echo "ERROR: Monitoring agent failed to start. Check logs with: journalctl -u monitoring-agent"
    exit 1
fi

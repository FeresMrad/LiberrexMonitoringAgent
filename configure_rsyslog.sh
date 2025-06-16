#!/bin/bash

# Rsyslog Configuration Script for Monitoring Agent
# Configures rsyslog to forward SSH and Apache logs to remote server

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

# Check if AGENT_ID is provided as parameter
if [ -z "$1" ]; then
    echo "ERROR: Agent ID must be provided as parameter"
    echo "Usage: $0 <AGENT_ID>"
    exit 1
fi

AGENT_ID="$1"

# Get remote log server from environment (required)
if [ -z "$REMOTE_LOG_SERVER" ]; then
    echo "ERROR: REMOTE_LOG_SERVER environment variable is required"
    echo "Please set REMOTE_LOG_SERVER in your .env file"
    exit 1
fi

echo "Configuring rsyslog for monitoring agent with ID: $AGENT_ID"
echo "Remote log server: $REMOTE_LOG_SERVER"

# Clean up any existing LocalHostName configuration to prevent duplicates
if grep -q "^\$LocalHostName" /etc/rsyslog.conf; then
    echo "Removing existing LocalHostName configuration from rsyslog.conf"
    sed -i '/^\$LocalHostName/d' /etc/rsyslog.conf
fi

# Remove any existing forwarding rules to prevent duplicates
if grep -q "@@${REMOTE_LOG_SERVER}" /etc/rsyslog.conf; then
    echo "Removing existing forwarding configuration from rsyslog.conf"
    sed -i "/@@${REMOTE_LOG_SERVER//./\\.}/d" /etc/rsyslog.conf
fi

# Remove any wildcard forwarding rules that send all logs
if grep -q "^\*\.\*" /etc/rsyslog.conf; then
    echo "Removing wildcard forwarding configuration from rsyslog.conf"
    sed -i '/^\*\.\*/d' /etc/rsyslog.conf
fi

# Add LocalHostName configuration to main rsyslog.conf
echo "Adding LocalHostName configuration to rsyslog.conf"
echo "\$LocalHostName $AGENT_ID" >> /etc/rsyslog.conf

# Remove old separate configuration files if they exist
OLD_CONFIGS=(
    "/etc/rsyslog.d/ssh-monitoring.conf"
    "/etc/rsyslog.d/apache-monitoring.conf"
    "/etc/rsyslog.d/monitoring.conf"
)

for config_file in "${OLD_CONFIGS[@]}"; do
    if [ -f "$config_file" ]; then
        echo "Removing old configuration file: $config_file"
        rm "$config_file"
    fi
done

# Create unified monitoring rsyslog configuration
echo "Creating unified monitoring rsyslog configuration"
cat > /etc/rsyslog.d/liberrex-monitoring.conf << EOL
###############################################################################
# Liberrex Monitoring Configuration
# Agent ID: $AGENT_ID
# Remote Server: $REMOTE_LOG_SERVER
# Generated: $(date)
###############################################################################

# Load imfile module for file monitoring
module(load="imfile" PollingInterval="10")

###############################################################################
# SSH Authentication Monitoring
###############################################################################
# Forward SSH daemon logs (authentication events)
if (\$programname == 'sshd') then {
    @@$REMOTE_LOG_SERVER
    stop
}

###############################################################################
# Apache Access Log Monitoring
###############################################################################
# Monitor Apache's main access log
input(type="imfile"
      File="/var/log/apache2/*access.log"
      Tag="apache-access:"
      Facility="local2"
      Severity="info"
      PersistStateInterval="200"
)

# Filter out monitoring and internal requests to reduce noise
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
    @@$REMOTE_LOG_SERVER
    stop
}

###############################################################################
# Error handling and queue configuration
###############################################################################
# Prevent infinite retries and disk space issues
\$ActionResumeRetryCount 0
\$ActionQueueType Direct

# Drop messages if remote server is unreachable for too long
\$ActionExecOnlyWhenPreviousIsSuspended on

###############################################################################
# End of Liberrex Monitoring Configuration
###############################################################################
EOL

echo "Created rsyslog configuration: /etc/rsyslog.d/liberrex-monitoring.conf"

# Test rsyslog configuration before applying
echo "Testing rsyslog configuration..."
if rsyslogd -N1 -f /etc/rsyslog.conf; then
    echo "✓ Rsyslog configuration test passed"
    
    # Restart rsyslog service to apply changes
    echo "Restarting rsyslog service..."
    if systemctl restart rsyslog; then
        echo "✓ Rsyslog service restarted successfully"
        
        # Wait a moment and check if rsyslog is running
        sleep 2
        if systemctl is-active --quiet rsyslog; then
            echo "✓ Rsyslog is running properly"
            
            # Verify our configuration file is being read
            if rsyslogd -N1 | grep -q "liberrex-monitoring.conf"; then
                echo "✓ Liberrex monitoring configuration loaded"
            fi
            
            exit 0
        else
            echo "✗ ERROR: Rsyslog service is not active after restart"
            exit 1
        fi
    else
        echo "✗ ERROR: Failed to restart rsyslog service"
        exit 1
    fi
else
    echo "✗ ERROR: Invalid rsyslog configuration detected"
    echo "Configuration files to check:"
    echo "- /etc/rsyslog.conf"
    echo "- /etc/rsyslog.d/liberrex-monitoring.conf"
    exit 1
fi

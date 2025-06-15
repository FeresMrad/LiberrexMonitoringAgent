#!/bin/bash

# Apache Configuration Script for Monitoring Agent
# Modifies Apache logging format to include response time for better monitoring

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "Configuring Apache for enhanced monitoring..."

# Check if Apache is installed
APACHE_CONFIG_FILE="/etc/apache2/apache2.conf"
if [ ! -f "$APACHE_CONFIG_FILE" ]; then
    echo "⚠ WARNING: Apache configuration not found at $APACHE_CONFIG_FILE"
    echo "Possible reasons:"
    echo "1. Apache is not installed"
    echo "2. Apache is installed in a different location"
    echo "3. Different Apache distribution (e.g., httpd instead of apache2)"
    echo ""
    echo "Skipping Apache configuration..."
    exit 0
fi

echo "✓ Apache configuration found at $APACHE_CONFIG_FILE"

# Create backup of apache2.conf before making changes
BACKUP_FILE="/etc/apache2/apache2.conf.backup.$(date +%Y%m%d_%H%M%S)"
echo "Creating backup of Apache configuration at $BACKUP_FILE"
cp "$APACHE_CONFIG_FILE" "$BACKUP_FILE"

# Function to check if LogFormat already includes response time (%D)
check_response_time_format() {
    local format_name="$1"
    local pattern="$2"
    
    if grep -q "$pattern" "$APACHE_CONFIG_FILE"; then
        if grep "$pattern" "$APACHE_CONFIG_FILE" | grep -q "%D"; then
            echo "✓ $format_name already includes response time (%D)"
            return 0
        else
            echo "→ $format_name needs response time (%D) added"
            return 1
        fi
    else
        echo "- $format_name not found (using custom format or default)"
        return 0
    fi
}

# Function to update LogFormat to include response time
update_logformat() {
    local format_name="$1"
    local old_pattern="$2"
    local new_pattern="$3"
    
    echo "Updating $format_name to include response time..."
    sed -i "s|$old_pattern|$new_pattern|g" "$APACHE_CONFIG_FILE"
}

echo "Checking Apache LogFormat configurations for response time (%D)..."

APACHE_MODIFIED=0

# Check and update vhost_combined format
if check_response_time_format "vhost_combined" 'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'; then
    : # Already has %D
else
    update_logformat "vhost_combined" \
        'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined' \
        'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'
    APACHE_MODIFIED=1
fi

# Check and update combined format
if check_response_time_format "combined" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'; then
    : # Already has %D
else
    update_logformat "combined" \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined' \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'
    APACHE_MODIFIED=1
fi

# Check and update common format
if check_response_time_format "common" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common'; then
    : # Already has %D
else
    update_logformat "common" \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common' \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O %D" common'
    APACHE_MODIFIED=1
fi

# Test Apache configuration before applying changes
echo "Testing Apache configuration..."
if apache2ctl configtest; then
    echo "✓ Apache configuration test passed"
    
    if [ $APACHE_MODIFIED -eq 1 ]; then
        echo "Apache logging formats updated - restarting Apache service..."
        
        if systemctl restart apache2; then
            echo "✓ Apache service restarted successfully"
            
            # Wait a moment and check if Apache is running
            sleep 2
            if systemctl is-active --quiet apache2; then
                echo "✓ Apache is running properly"
                
                # Show current LogFormat configurations
                echo ""
                echo "Current Apache LogFormat configurations:"
                grep "^LogFormat" "$APACHE_CONFIG_FILE" | while read -r line; do
                    if echo "$line" | grep -q "%D"; then
                        echo "✓ $line"
                    else
                        echo "- $line"
                    fi
                done
                
                # Create a marker file to indicate Apache was restarted by this script
                touch "/tmp/apache_restarted_by_monitoring_agent"
                
                exit 0
            else
                echo "✗ ERROR: Apache service is not active after restart"
                echo "Restoring backup configuration..."
                cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
                systemctl restart apache2
                exit 1
            fi
        else
            echo "✗ ERROR: Failed to restart Apache service"
            echo "Restoring backup configuration..."
            cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
            exit 1
        fi
    else
        echo "✓ Apache logging formats already include response time or use custom formats"
        echo "No Apache restart needed"
        exit 0
    fi
else
    echo "✗ ERROR: Apache configuration test failed"
    echo "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
    exit 1
fi

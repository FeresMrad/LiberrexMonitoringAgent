#!/bin/bash

# Apache Configuration Script for Monitoring Agent
# Modifies Apache logging format to include virtual host (%v) and response time (%D) for better monitoring

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 
   exit 1
fi

echo "Configuring Apache for enhanced monitoring with virtual host and response time..."

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

# Function to check if LogFormat already includes virtual host (%v) and response time (%D)
check_enhanced_format() {
    local format_name="$1"
    local pattern="$2"
    
    if grep -q "$pattern" "$APACHE_CONFIG_FILE"; then
        local format_line=$(grep "$pattern" "$APACHE_CONFIG_FILE")
        local has_vhost=$(echo "$format_line" | grep -c "%v")
        local has_response_time=$(echo "$format_line" | grep -c "%D")
        
        if [ $has_vhost -gt 0 ] && [ $has_response_time -gt 0 ]; then
            echo "✓ $format_name already includes virtual host (%v) and response time (%D)"
            return 0
        elif [ $has_vhost -gt 0 ]; then
            echo "→ $format_name has virtual host (%v) but needs response time (%D) added"
            return 1
        elif [ $has_response_time -gt 0 ]; then
            echo "→ $format_name has response time (%D) but needs virtual host (%v) added"
            return 2
        else
            echo "→ $format_name needs both virtual host (%v) and response time (%D) added"
            return 3
        fi
    else
        echo "- $format_name not found (using custom format or default)"
        return 0
    fi
}

# Function to update LogFormat to include virtual host and response time
update_logformat() {
    local format_name="$1"
    local old_pattern="$2"
    local new_pattern="$3"
    
    echo "Updating $format_name to include virtual host (%v) and response time (%D)..."
    sed -i "s|$old_pattern|$new_pattern|g" "$APACHE_CONFIG_FILE"
}

echo "Checking Apache LogFormat configurations for virtual host (%v) and response time (%D)..."

APACHE_MODIFIED=0

# Check and update vhost_combined format
# Note: vhost_combined already has %v:%p at the start, we just need to add %D
if check_enhanced_format "vhost_combined" 'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'; then
    : # Already has both %v and %D
else
    update_logformat "vhost_combined" \
        'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined' \
        'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'
    APACHE_MODIFIED=1
fi

# Check and update combined format (add %v at start and %D after %O)
if check_enhanced_format "combined" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'; then
    : # Already has both %v and %D
else
    update_logformat "combined" \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined' \
        'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'
    APACHE_MODIFIED=1
fi

# Check and update common format (add %v at start and %D after %O)
if check_enhanced_format "common" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common'; then
    : # Already has both %v and %D
else
    update_logformat "common" \
        'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common' \
        'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D" common'
    APACHE_MODIFIED=1
fi

# Also handle any alternative formats that might exist
# Check for formats without the escape sequences (some distributions use different escaping)
if grep -q 'LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined' "$APACHE_CONFIG_FILE"; then
    echo "Found alternative combined format (without escape sequences)"
    if ! grep -q '%v.*%h %l %u %t.*%D' "$APACHE_CONFIG_FILE"; then
        update_logformat "combined (alternative)" \
            'LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined' \
            'LogFormat "%v %h %l %u %t \"%r\" %>s %O %D \"%{Referer}i\" \"%{User-Agent}i\"" combined'
        APACHE_MODIFIED=1
    fi
fi

if grep -q 'LogFormat "%h %l %u %t \"%r\" %>s %O" common' "$APACHE_CONFIG_FILE"; then
    echo "Found alternative common format (without escape sequences)"
    if ! grep -q '%v.*%h %l %u %t.*%D' "$APACHE_CONFIG_FILE"; then
        update_logformat "common (alternative)" \
            'LogFormat "%h %l %u %t \"%r\" %>s %O" common' \
            'LogFormat "%v %h %l %u %t \"%r\" %>s %O %D" common'
        APACHE_MODIFIED=1
    fi
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
                    local has_vhost=$(echo "$line" | grep -c "%v")
                    local has_response_time=$(echo "$line" | grep -c "%D")
                    
                    if [ $has_vhost -gt 0 ] && [ $has_response_time -gt 0 ]; then
                        echo "✓ $line"
                    elif [ $has_vhost -gt 0 ] || [ $has_response_time -gt 0 ]; then
                        echo "◐ $line"
                    else
                        echo "- $line"
                    fi
                done
                
                echo ""
                echo "Log format legend:"
                echo "✓ = Has both virtual host (%v) and response time (%D)"
                echo "◐ = Has either virtual host (%v) or response time (%D)"
                echo "- = Standard format without enhancements"
                
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
        echo "✓ Apache logging formats already include virtual host and response time or use custom formats"
        echo "No Apache restart needed"
        
        # Show current LogFormat configurations anyway
        echo ""
        echo "Current Apache LogFormat configurations:"
        grep "^LogFormat" "$APACHE_CONFIG_FILE" | while read -r line; do
            local has_vhost=$(echo "$line" | grep -c "%v")
            local has_response_time=$(echo "$line" | grep -c "%D")
            
            if [ $has_vhost -gt 0 ] && [ $has_response_time -gt 0 ]; then
                echo "✓ $line"
            elif [ $has_vhost -gt 0 ] || [ $has_response_time -gt 0 ]; then
                echo "◐ $line"
            else
                echo "- $line"
            fi
        done
        
        exit 0
    fi
else
    echo "✗ ERROR: Apache configuration test failed"
    echo "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
    exit 1
fi

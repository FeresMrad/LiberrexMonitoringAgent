#!/bin/bash

# Apache Configuration Script for Monitoring Agent
# Modifies Apache logging format to include virtual host and response time for better monitoring

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

# Function to check if LogFormat already includes virtual host (%v) and response time (%D)
check_enhanced_format() {
    local format_name="$1"
    local pattern="$2"
    
    if grep -q "$pattern" "$APACHE_CONFIG_FILE"; then
        local format_line=$(grep "$pattern" "$APACHE_CONFIG_FILE")
        local has_vhost=$(echo "$format_line" | grep -q "%v" && echo "true" || echo "false")
        local has_response_time=$(echo "$format_line" | grep -q "%D" && echo "true" || echo "false")
        
        if [ "$has_vhost" = "true" ] && [ "$has_response_time" = "true" ]; then
            echo "✓ $format_name already includes virtual host (%v) and response time (%D)"
            return 0
        elif [ "$has_vhost" = "true" ] && [ "$has_response_time" = "false" ]; then
            echo "→ $format_name has virtual host (%v) but needs response time (%D) added"
            return 1
        elif [ "$has_vhost" = "false" ] && [ "$has_response_time" = "true" ]; then
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
# Note: vhost_combined already has %v:%p at the start, we just need to ensure %D is present
if check_enhanced_format "vhost_combined" 'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'; then
    : # Already has both %v and %D
else
    case $? in
        1) # Has %v, needs %D
            update_logformat "vhost_combined" \
                'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined' \
                'LogFormat "%v:%p %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" vhost_combined'
            APACHE_MODIFIED=1
            ;;
        *) # Other cases shouldn't happen for vhost_combined as it already has %v:%p
            : # Do nothing
            ;;
    esac
fi

# Check and update combined format (add %v at start and %D after %O)
if check_enhanced_format "combined" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'; then
    : # Already has both %v and %D
else
    case $? in
        1) # Has %v, needs %D
            # This case should not happen as we're checking the original pattern without %v
            # But handle it just in case
            local current_line=$(grep 'LogFormat ".*" combined' "$APACHE_CONFIG_FILE")
            if echo "$current_line" | grep -q "%v" && ! echo "$current_line" | grep -q "%D"; then
                # Add %D after %O
                sed -i 's/LogFormat "\(%v[^"]*%O\) \(.*\)" combined/LogFormat "\1 %D \2" combined/g' "$APACHE_CONFIG_FILE"
                APACHE_MODIFIED=1
            fi
            ;;
        2) # Has %D, needs %v
            # Add %v at the beginning
            update_logformat "combined" \
                'LogFormat "%h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined' \
                'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'
            APACHE_MODIFIED=1
            ;;
        3) # Needs both %v and %D
            update_logformat "combined" \
                'LogFormat "%h %l %u %t \\"%r\\" %>s %O \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined' \
                'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D \\"%{Referer}i\\" \\"%{User-Agent}i\\"" combined'
            APACHE_MODIFIED=1
            ;;
    esac
fi

# Check and update common format (add %v at start and %D after %O)
if check_enhanced_format "common" 'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common'; then
    : # Already has both %v and %D
else
    case $? in
        1) # Has %v, needs %D
            # This case should not happen as we're checking the original pattern without %v
            # But handle it just in case
            local current_line=$(grep 'LogFormat ".*" common' "$APACHE_CONFIG_FILE")
            if echo "$current_line" | grep -q "%v" && ! echo "$current_line" | grep -q "%D"; then
                # Add %D after %O
                sed -i 's/LogFormat "\(%v[^"]*%O\) \(.*\)" common/LogFormat "\1 %D \2" common/g' "$APACHE_CONFIG_FILE"
                APACHE_MODIFIED=1
            fi
            ;;
        2) # Has %D, needs %v
            # Add %v at the beginning
            update_logformat "common" \
                'LogFormat "%h %l %u %t \\"%r\\" %>s %O %D" common' \
                'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D" common'
            APACHE_MODIFIED=1
            ;;
        3) # Needs both %v and %D
            update_logformat "common" \
                'LogFormat "%h %l %u %t \\"%r\\" %>s %O" common' \
                'LogFormat "%v %h %l %u %t \\"%r\\" %>s %O %D" common'
            APACHE_MODIFIED=1
            ;;
    esac
fi

# Check for other common LogFormat patterns that might exist and update them
# This handles custom formats that might be in use

# Function to update any LogFormat that doesn't have %v at start or %D
update_custom_logformats() {
    echo "Checking for other LogFormat entries that need enhancement..."
    
    # Find all LogFormat lines
    while IFS= read -r line; do
        if [[ "$line" =~ ^LogFormat ]]; then
            # Skip if it already has %v at the start and %D somewhere
            if echo "$line" | grep -q '"%v' && echo "$line" | grep -q '%D'; then
                continue
            fi
            
            # Extract the format name
            local format_name=$(echo "$line" | sed -n 's/.*" \([a-zA-Z_][a-zA-Z0-9_]*\)$/\1/p')
            
            if [ -n "$format_name" ] && [ "$format_name" != "combined" ] && [ "$format_name" != "common" ] && [ "$format_name" != "vhost_combined" ]; then
                echo "Found custom LogFormat: $format_name"
                
                # Check if it needs %v at start
                if ! echo "$line" | grep -q '"%v'; then
                    echo "  → Adding %v to start of $format_name"
                    # Add %v at the beginning of the format string
                    sed -i "s/LogFormat \"\([^\"]*\)\" $format_name/LogFormat \"%v \1\" $format_name/g" "$APACHE_CONFIG_FILE"
                    APACHE_MODIFIED=1
                fi
                
                # Check if it needs %D (look for %O and add %D after it)
                if ! echo "$line" | grep -q '%D' && echo "$line" | grep -q '%O'; then
                    echo "  → Adding %D after %O in $format_name"
                    # Add %D after %O
                    sed -i "s/LogFormat \"\([^\"]*%O\) \([^\"]*\)\" $format_name/LogFormat \"\1 %D \2\" $format_name/g" "$APACHE_CONFIG_FILE"
                    APACHE_MODIFIED=1
                fi
            fi
        fi
    done < "$APACHE_CONFIG_FILE"
}

# Update any custom LogFormats
update_custom_logformats

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
                    local has_vhost=$(echo "$line" | grep -q "%v" && echo "✓" || echo "✗")
                    local has_response_time=$(echo "$line" | grep -q "%D" && echo "✓" || echo "✗")
                    echo "$has_vhost$has_response_time $line"
                done
                
                echo ""
                echo "Legend: First symbol = Virtual Host (%v), Second symbol = Response Time (%D)"
                echo "✓✓ = Both present, ✗✓ = Missing %v, ✓✗ = Missing %D, ✗✗ = Missing both"
                
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
        echo "✓ Apache logging formats already include virtual host (%v) and response time (%D)"
        echo "No Apache restart needed"
        
        # Still show current configurations for verification
        echo ""
        echo "Current Apache LogFormat configurations:"
        grep "^LogFormat" "$APACHE_CONFIG_FILE" | while read -r line; do
            local has_vhost=$(echo "$line" | grep -q "%v" && echo "✓" || echo "✗")
            local has_response_time=$(echo "$line" | grep -q "%D" && echo "✓" || echo "✗")
            echo "$has_vhost$has_response_time $line"
        done
        
        exit 0
    fi
else
    echo "✗ ERROR: Apache configuration test failed"
    echo "Restoring backup configuration..."
    cp "$BACKUP_FILE" "$APACHE_CONFIG_FILE"
    exit 1
fi

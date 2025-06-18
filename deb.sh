#!/bin/bash

echo "=== SYSTEM DIAGNOSTIC FOR SSH MONITORING ==="
echo "Date: $(date)"
echo "User: $(whoami)"
echo "PATH: $PATH"
echo ""

echo "=== CHECKING REQUIRED COMMANDS ==="
commands=("who" "w" "netstat" "ss" "ps")

for cmd in "${commands[@]}"; do
    echo -n "Checking $cmd: "
    if command -v "$cmd" >/dev/null 2>&1; then
        full_path=$(command -v "$cmd")
        echo "✓ Found at $full_path"
        
        # Test the command
        case "$cmd" in
            "who")
                echo "  Testing 'who':"
                who 2>&1 | head -3 | sed 's/^/    /'
                ;;
            "w")
                echo "  Testing 'w -h':"
                w -h 2>&1 | head -3 | sed 's/^/    /'
                ;;
            "netstat")
                echo "  Testing 'netstat -tn | grep :22':"
                netstat -tn 2>/dev/null | grep :22 | head -3 | sed 's/^/    /' || echo "    No SSH connections found"
                ;;
            "ss")
                echo "  Testing 'ss -tn sport = :22':"
                ss -tn sport = :22 2>/dev/null | head -3 | sed 's/^/    /' || echo "    No SSH connections found"
                ;;
            "ps")
                echo "  Testing 'ps aux | grep sshd':"
                ps aux 2>/dev/null | grep sshd | grep -v grep | head -3 | sed 's/^/    /' || echo "    No sshd processes found"
                ;;
        esac
        echo ""
    else
        echo "✗ Not found"
        
        # Check common locations
        echo "  Checking common locations:"
        for path in /usr/bin /bin /usr/local/bin /sbin /usr/sbin; do
            if [ -f "$path/$cmd" ]; then
                echo "    Found at $path/$cmd"
            fi
        done
        echo ""
    fi
done

echo "=== CHECKING /proc FILESYSTEM ==="
if [ -d "/proc" ]; then
    echo "✓ /proc filesystem available"
    echo "  Sample process directories:"
    ls /proc | grep '^[0-9]*$' | head -5 | sed 's/^/    /'
    
    echo "  Checking for SSH processes in /proc:"
    found_ssh=false
    for pid_dir in /proc/[0-9]*; do
        if [ -r "$pid_dir/cmdline" ]; then
            cmdline=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null)
            if [[ "$cmdline" == *"sshd:"* ]]; then
                echo "    Found SSH process: $cmdline"
                found_ssh=true
            fi
        fi
    done
    
    if [ "$found_ssh" = false ]; then
        echo "    No SSH processes found in /proc"
    fi
else
    echo "✗ /proc filesystem not available"
fi

echo ""
echo "=== CURRENT SSH SESSIONS (if any) ==="
echo "Current user sessions:"
if command -v who >/dev/null 2>&1; then
    who
elif command -v w >/dev/null 2>&1; then
    w
else
    echo "No session listing command available"
fi

echo ""
echo "=== SSH DAEMON STATUS ==="
if command -v systemctl >/dev/null 2>&1; then
    echo "SSH daemon status:"
    systemctl status ssh 2>/dev/null || systemctl status sshd 2>/dev/null || echo "SSH daemon not found via systemctl"
else
    echo "systemctl not available"
fi

echo ""
echo "=== NETWORK CONNECTIONS ON PORT 22 ==="
if command -v netstat >/dev/null 2>&1; then
    echo "netstat output for port 22:"
    netstat -tn 2>/dev/null | grep :22 || echo "No connections on port 22"
elif command -v ss >/dev/null 2>&1; then
    echo "ss output for port 22:"
    ss -tn sport = :22 2>/dev/null || echo "No connections on port 22"
else
    echo "No network monitoring command available"
fi

echo ""
echo "=== RECOMMENDATIONS ==="
echo "Based on available commands, the SSH collector should use:"

if command -v who >/dev/null 2>&1; then
    echo "1. 'who' command (preferred)"
elif command -v w >/dev/null 2>&1; then
    echo "1. 'w' command (good alternative)"
else
    echo "1. /proc filesystem method (fallback)"
fi

if command -v netstat >/dev/null 2>&1; then
    echo "2. 'netstat' for connection counting"
elif command -v ss >/dev/null 2>&1; then
    echo "2. 'ss' for connection counting"
fi

echo ""
echo "=== END DIAGNOSTIC ==="

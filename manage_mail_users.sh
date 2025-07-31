#!/bin/bash

# Virtual Mail User Management Script
# For Postfix + Dovecot Virtual Users Setup
# Usage: ./manage_mail_users.sh [add|remove|password|list|help]

# Configuration
DOVECOT_USERS="/etc/dovecot/users"
POSTFIX_VMAILBOX="/etc/postfix/vmailbox"
POSTFIX_VIRTUAL="/etc/postfix/virtual"
VMAIL_BASE="/var/mail/vhosts"
VMAIL_USER="vmail"
VMAIL_UID="5000"
VMAIL_GID="5000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ Error: $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠ Warning: $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ Info: $1${NC}"; }

# Function to check if running as root or with sudo
check_privileges() {
    if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
        print_error "This script requires root privileges or sudo access."
        exit 1
    fi
}

# Function to validate email format
validate_email() {
    local email="$1"
    local regex="^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    
    if [[ ! $email =~ $regex ]]; then
        print_error "Invalid email format: $email"
        return 1
    fi
    return 0
}

# Function to check if user exists
user_exists() {
    local email="$1"
    if sudo grep -q "^$email:" "$DOVECOT_USERS" 2>/dev/null; then
        return 0
    fi
    return 1
}

# Function to get configured domains
get_configured_domains() {
    if [[ -f "$POSTFIX_VMAILBOX" ]]; then
        sudo awk -F'@' '{print $2}' "$POSTFIX_VMAILBOX" | awk '{print $1}' | sort -u | grep -v '^$'
    fi
}

# Function to add a virtual mail user
add_user() {
    local email domain username password password_hash
    
    if [[ -n "$1" ]]; then
        email="$1"
    else
        read -p "Enter email address (user@domain.com): " email
    fi
    
    # Validate email format
    if ! validate_email "$email"; then
        return 1
    fi
    
    # Check if user already exists
    if user_exists "$email"; then
        print_error "User $email already exists!"
        return 1
    fi
    
    # Extract domain and username
    domain=$(echo "$email" | cut -d'@' -f2)
    username=$(echo "$email" | cut -d'@' -f1)
    
    # Get configured domains for validation
    configured_domains=$(get_configured_domains)
    if [[ -n "$configured_domains" ]] && ! echo "$configured_domains" | grep -q "^$domain$"; then
        print_warning "Domain $domain is not in the configured domains list."
        print_info "Configured domains: $(echo $configured_domains | tr '\n' ' ')"
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [[ "$continue_anyway" != "yes" ]]; then
            print_info "User creation cancelled."
            return 1
        fi
    fi
    
    # Get password
    if [[ -n "$2" ]]; then
        password="$2"
    else
        read -s -p "Enter password for $email: " password
        echo
        read -s -p "Confirm password: " password_confirm
        echo
        
        if [[ "$password" != "$password_confirm" ]]; then
            print_error "Passwords do not match!"
            return 1
        fi
    fi
    
    if [[ -z "$password" ]]; then
        print_error "Password cannot be empty!"
        return 1
    fi
    
    print_info "Creating virtual mail user: $email"
    
    # Generate password hash
    password_hash=$(doveadm pw -s BLF-CRYPT -p "$password" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        print_error "Failed to generate password hash. Is doveadm installed?"
        return 1
    fi
    
    # Add user to Dovecot users file
    echo "$email:$password_hash::::" | sudo tee -a "$DOVECOT_USERS" > /dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Failed to add user to Dovecot users file"
        return 1
    fi
    
    # Add user to Postfix virtual mailbox file
    echo "$email $domain/$username/" | sudo tee -a "$POSTFIX_VMAILBOX" > /dev/null
    if [[ $? -ne 0 ]]; then
        print_error "Failed to add user to Postfix virtual mailbox file"
        return 1
    fi
    
    # Create user directory structure
    sudo mkdir -p "$VMAIL_BASE/$domain/$username/Maildir/{cur,new,tmp}"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create user directory structure"
        return 1
    fi
    
    # Set proper ownership and permissions
    sudo chown -R "$VMAIL_USER:$VMAIL_USER" "$VMAIL_BASE/$domain/$username"
    sudo chmod -R 700 "$VMAIL_BASE/$domain/$username"
    
    # Rebuild Postfix maps
    sudo postmap "$POSTFIX_VMAILBOX"
    if [[ -f "$POSTFIX_VIRTUAL" ]]; then
        sudo postmap "$POSTFIX_VIRTUAL"
    fi
    
    # Reload services
    sudo systemctl reload postfix
    sudo systemctl reload dovecot
    
    print_success "Virtual mail user $email added successfully"
    print_info "Mailbox location: $VMAIL_BASE/$domain/$username/Maildir"
}

# Function to remove a virtual mail user
remove_user() {
    local email domain username
    
    if [[ -n "$1" ]]; then
        email="$1"
    else
        read -p "Enter email address to remove: " email
    fi
    
    # Validate email format
    if ! validate_email "$email"; then
        return 1
    fi
    
    # Check if user exists
    if ! user_exists "$email"; then
        print_error "User $email does not exist!"
        return 1
    fi
    
    # Extract domain and username
    domain=$(echo "$email" | cut -d'@' -f2)
    username=$(echo "$email" | cut -d'@' -f1)
    
    # Confirm deletion
    print_warning "This will permanently delete the user $email and all their emails!"
    read -p "Are you sure you want to continue? (yes/no): " confirm
    if [[ "$confirm" != "yes" ]]; then
        print_info "User deletion cancelled."
        return 1
    fi
    
    print_info "Removing virtual mail user: $email"
    
    # Remove user from Dovecot users file
    sudo sed -i "/^$email:/d" "$DOVECOT_USERS"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to remove user from Dovecot users file"
        return 1
    fi
    
    # Remove user from Postfix virtual mailbox file
    sudo sed -i "/^$email /d" "$POSTFIX_VMAILBOX"
    if [[ $? -ne 0 ]]; then
        print_error "Failed to remove user from Postfix virtual mailbox file"
        return 1
    fi
    
    # Remove user directory
    if [[ -d "$VMAIL_BASE/$domain/$username" ]]; then
        sudo rm -rf "$VMAIL_BASE/$domain/$username"
        print_info "User mailbox directory removed: $VMAIL_BASE/$domain/$username"
    fi
    
    # Rebuild Postfix maps
    sudo postmap "$POSTFIX_VMAILBOX"
    if [[ -f "$POSTFIX_VIRTUAL" ]]; then
        sudo postmap "$POSTFIX_VIRTUAL"
    fi
    
    # Reload services
    sudo systemctl reload postfix
    sudo systemctl reload dovecot
    
    print_success "Virtual mail user $email removed successfully"
}

# Function to change user password
change_password() {
    local email password password_hash
    
    if [[ -n "$1" ]]; then
        email="$1"
    else
        read -p "Enter email address: " email
    fi
    
    # Validate email format
    if ! validate_email "$email"; then
        return 1
    fi
    
    # Check if user exists
    if ! user_exists "$email"; then
        print_error "User $email does not exist!"
        return 1
    fi
    
    # Get new password
    if [[ -n "$2" ]]; then
        password="$2"
    else
        read -s -p "Enter new password for $email: " password
        echo
        read -s -p "Confirm new password: " password_confirm
        echo
        
        if [[ "$password" != "$password_confirm" ]]; then
            print_error "Passwords do not match!"
            return 1
        fi
    fi
    
    if [[ -z "$password" ]]; then
        print_error "Password cannot be empty!"
        return 1
    fi
    
    print_info "Changing password for: $email"
    
    # Generate new password hash
    password_hash=$(doveadm pw -s BLF-CRYPT -p "$password" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        print_error "Failed to generate password hash. Is doveadm installed?"
        return 1
    fi
    
    # Create temporary file with new password
    temp_file=$(mktemp)
    sudo awk -v email="$email" -v hash="$password_hash" '
        BEGIN { FS=OFS=":" }
        $1 == email { $2 = hash; print; next }
        { print }
    ' "$DOVECOT_USERS" > "$temp_file"
    
    # Replace the original file
    sudo cp "$temp_file" "$DOVECOT_USERS"
    sudo rm "$temp_file"
    
    # Set proper permissions
    sudo chmod 600 "$DOVECOT_USERS"
    sudo chown root:dovecot "$DOVECOT_USERS"
    
    # Reload Dovecot
    sudo systemctl reload dovecot
    
    print_success "Password changed successfully for $email"
}

# Function to list all virtual mail users
list_users() {
    print_info "Virtual Mail Users:"
    echo "===================="
    
    if [[ ! -f "$DOVECOT_USERS" ]]; then
        print_warning "No users file found at $DOVECOT_USERS"
        return 1
    fi
    
    local user_count=0
    while IFS=':' read -r email hash uid gid gecos home shell; do
        if [[ -n "$email" ]]; then
            domain=$(echo "$email" | cut -d'@' -f2)
            username=$(echo "$email" | cut -d'@' -f1)
            mailbox_path="$VMAIL_BASE/$domain/$username/Maildir"
            
            # Check if mailbox directory exists
            if [[ -d "$mailbox_path" ]]; then
                status="${GREEN}✓ Active${NC}"
            else
                status="${RED}✗ Missing Mailbox${NC}"
            fi
            
            echo -e "$email - $status"
            ((user_count++))
        fi
    done < <(sudo cat "$DOVECOT_USERS" 2>/dev/null)
    
    echo "===================="
    print_info "Total users: $user_count"
}

# Function to show usage
show_help() {
    echo "Virtual Mail User Management Script"
    echo "=================================="
    echo
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  add [email] [password]    Add a new virtual mail user"
    echo "  remove [email]            Remove a virtual mail user"
    echo "  password [email] [pass]   Change user password"
    echo "  list                      List all virtual mail users"
    echo "  help                      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 add user@example.com"
    echo "  $0 add user@example.com mypassword"
    echo "  $0 remove user@example.com"
    echo "  $0 password user@example.com"
    echo "  $0 password user@example.com newpassword"
    echo "  $0 list"
    echo
    echo "Interactive mode:"
    echo "  $0                        Run in interactive mode"
    echo
}

# Interactive menu
interactive_menu() {
    while true; do
        echo
        echo "=================================="
        echo "Virtual Mail User Management"
        echo "=================================="
        echo "1. Add user"
        echo "2. Remove user"
        echo "3. Change password"
        echo "4. List users"
        echo "5. Help"
        echo "6. Exit"
        echo
        read -p "Select an option (1-6): " choice
        
        case $choice in
            1)
                add_user
                ;;
            2)
                remove_user
                ;;
            3)
                change_password
                ;;
            4)
                list_users
                ;;
            5)
                show_help
                ;;
            6)
                print_info "Goodbye!"
                exit 0
                ;;
            *)
                print_error "Invalid option. Please select 1-6."
                ;;
        esac
    done
}

# Main script logic
main() {
    # Check privileges
    check_privileges
    
    # Parse command line arguments
    case "${1:-}" in
        "add")
            add_user "$2" "$3"
            ;;
        "remove")
            remove_user "$2"
            ;;
        "password")
            change_password "$2" "$3"
            ;;
        "list")
            list_users
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "")
            interactive_menu
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function
main "$@"

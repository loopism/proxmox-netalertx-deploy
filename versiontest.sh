#!/bin/bash

extract_ubuntu_templates() {
    pveam available 2>/dev/null | grep -Eo 'ubuntu-[0-9]+\.[0-9]+-standard_[^[:space:]]+' | sort -u
}

# Function to select Ubuntu template
select_ubuntu_template() {
    local version=$1
    local major="$version"
    local template
    template=$(extract_ubuntu_templates | grep -E "ubuntu-${major}\.[0-9]+-standard_" | sort -u | head -n1)
    if [ -z "$template" ]; then
        print_error "No template matching Ubuntu major version ${major} found"
        exit 1
    fi
    echo "$template"
}

get_ubuntu_templates_by_major() {
    local major=$1
    extract_ubuntu_templates | grep -E "ubuntu-${major}\.[0-9]+-standard_" | sort -u
}

get_ubuntu_major_options() {
    extract_ubuntu_templates | sed -E 's/ubuntu-([0-9]+)\..*/\1/' | sort -u
}

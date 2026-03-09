#!/usr/bin/env bash
#
# Claude Code Global Skills Installer
#
# Symlinks all 65 skills from this repository into ~/.claude/skills/
# so they're available globally in every Claude Code session.
#
# Skills are live-linked — run `git pull` then re-run this script to update.
#
# Usage:
#   ./scripts/claude-code-install.sh              # Install all skills
#   ./scripts/claude-code-install.sh --dry-run     # Preview without changes
#   ./scripts/claude-code-install.sh --uninstall   # Remove all symlinks
#   ./scripts/claude-code-install.sh --status       # Show what's installed
#   ./scripts/claude-code-install.sh --category engineering-team  # Install one domain
#   ./scripts/claude-code-install.sh --help        # Show help
#

set -euo pipefail

# Configuration
CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Domains containing skills (directories with skill subdirs that have SKILL.md)
DOMAINS=(
    "marketing-skill"
    "product-team"
    "project-management"
    "engineering-team"
    "engineering"
    "c-level-advisor"
    "business-growth"
    "ra-qm-team"
    "finance"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Counters
installed=0
updated=0
skipped=0
failed=0
removed=0

print_banner() {
    echo ""
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Claude Skills — Global Installer${NC}"
    echo -e "${BOLD}════════════════════════════════════════════${NC}"
    echo -e "  Repository: ${CYAN}${REPO_DIR}${NC}"
    echo -e "  Target:     ${CYAN}${CLAUDE_SKILLS_DIR}${NC}"
    echo ""
}

show_help() {
    cat << 'EOF'
Claude Code Global Skills Installer

Symlinks skills from this repository into ~/.claude/skills/ for global access.

USAGE:
    ./scripts/claude-code-install.sh [OPTIONS]

OPTIONS:
    (none)              Install/update all 65 skills
    --dry-run           Preview what would be installed (no changes)
    --uninstall         Remove all repo-linked symlinks from ~/.claude/skills/
    --status            Show currently installed skills from this repo
    --category <name>   Install only skills from a specific domain
    --list              List all available skills grouped by domain
    --help              Show this help message

CATEGORIES:
    marketing-skill     6 skills  (content, SEO, demand gen, campaigns)
    product-team        5 skills  (PM, product strategy, UX, design systems)
    project-management  6 skills  (Jira, Confluence, Scrum, PM)
    engineering-team   19 skills  (fullstack, backend, frontend, DevOps, AI/ML)
    engineering        11 skills  (API design, database, RAG, tech debt)
    c-level-advisor     2 skills  (CEO advisor, CTO advisor)
    business-growth     3 skills  (sales, customer success, revenue ops)
    ra-qm-team        12 skills  (ISO 13485, MDR, FDA, GDPR, auditing)
    finance             1 skill   (financial analyst)

EXAMPLES:
    ./scripts/claude-code-install.sh                          # Install all
    ./scripts/claude-code-install.sh --dry-run                # Preview
    ./scripts/claude-code-install.sh --category engineering   # One domain
    ./scripts/claude-code-install.sh --uninstall              # Remove all

UPDATING:
    git pull && ./scripts/claude-code-install.sh

    Symlinks point to the repo, so pulling updates the skill content.
    Re-running the script picks up any new skills added since last install.
EOF
    exit 0
}

# Find all valid skills in a domain directory
find_skills_in_domain() {
    local domain="$1"
    local domain_path="${REPO_DIR}/${domain}"

    if [[ ! -d "$domain_path" ]]; then
        return
    fi

    for skill_dir in "$domain_path"/*/; do
        [[ ! -d "$skill_dir" ]] && continue
        local skill_name
        skill_name="$(basename "$skill_dir")"

        # Skip hidden dirs and non-skill dirs
        [[ "$skill_name" == .* ]] && continue

        # Must have SKILL.md directly (not nested in assets/)
        if [[ -f "${skill_dir}SKILL.md" ]]; then
            echo "${domain}/${skill_name}"
        fi
    done
}

# Install a single skill
install_skill() {
    local domain_skill="$1"
    local dry_run="$2"
    local domain="${domain_skill%%/*}"
    local skill_name="${domain_skill##*/}"
    local source="${REPO_DIR}/${domain}/${skill_name}"
    local target="${CLAUDE_SKILLS_DIR}/${skill_name}"

    # Validate source
    if [[ ! -f "${source}/SKILL.md" ]]; then
        echo -e "  ${RED}SKIP${NC}  ${skill_name} (no SKILL.md)"
        ((failed++)) || true
        return 1
    fi

    if [[ "$dry_run" == "true" ]]; then
        if [[ -L "$target" ]]; then
            local existing_target
            existing_target="$(readlink -f "$target" 2>/dev/null || echo "")"
            if [[ "$existing_target" == "$(readlink -f "$source")" ]]; then
                echo -e "  ${YELLOW}OK${NC}    ${skill_name} (already linked)"
                ((skipped++)) || true
            else
                echo -e "  ${BLUE}UPDATE${NC} ${skill_name} (would relink)"
                ((updated++)) || true
            fi
        elif [[ -e "$target" ]]; then
            echo -e "  ${YELLOW}WARN${NC}  ${skill_name} (exists, not a symlink — would skip)"
            ((skipped++)) || true
        else
            echo -e "  ${GREEN}NEW${NC}   ${skill_name}"
            ((installed++)) || true
        fi
        return 0
    fi

    # Create skills dir if needed
    mkdir -p "$CLAUDE_SKILLS_DIR"

    # Handle existing target
    if [[ -L "$target" ]]; then
        local existing_target
        existing_target="$(readlink -f "$target" 2>/dev/null || echo "")"
        if [[ "$existing_target" == "$(readlink -f "$source")" ]]; then
            ((skipped++)) || true
            return 0
        fi
        # Different source — update the symlink
        rm "$target"
        ln -s "$source" "$target"
        echo -e "  ${BLUE}UPDATE${NC} ${skill_name}"
        ((updated++)) || true
    elif [[ -e "$target" ]]; then
        # Real directory exists (not our symlink) — don't clobber
        echo -e "  ${YELLOW}SKIP${NC}  ${skill_name} (directory exists, not a symlink)"
        ((skipped++)) || true
    else
        ln -s "$source" "$target"
        echo -e "  ${GREEN}NEW${NC}   ${skill_name}"
        ((installed++)) || true
    fi
}

# Install skills from specific domains
install_domains() {
    local dry_run="$1"
    shift
    local domains=("$@")

    for domain in "${domains[@]}"; do
        local domain_path="${REPO_DIR}/${domain}"
        if [[ ! -d "$domain_path" ]]; then
            echo -e "  ${RED}ERROR${NC} Domain not found: ${domain}"
            continue
        fi

        local count=0
        while IFS= read -r skill; do
            [[ -z "$skill" ]] && continue
            ((count++)) || true
        done < <(find_skills_in_domain "$domain")

        echo -e "${BOLD}${domain}${NC} (${count} skills)"

        while IFS= read -r domain_skill; do
            [[ -z "$domain_skill" ]] && continue
            install_skill "$domain_skill" "$dry_run"
        done < <(find_skills_in_domain "$domain")
        echo ""
    done
}

# Uninstall all repo-linked symlinks
uninstall_all() {
    echo -e "${BOLD}Removing repo-linked skills from ${CLAUDE_SKILLS_DIR}${NC}"
    echo ""

    if [[ ! -d "$CLAUDE_SKILLS_DIR" ]]; then
        echo "Skills directory doesn't exist. Nothing to remove."
        exit 0
    fi

    for target in "$CLAUDE_SKILLS_DIR"/*/; do
        [[ ! -L "${target%/}" ]] && continue
        local link_target
        link_target="$(readlink -f "${target%/}" 2>/dev/null || echo "")"

        # Only remove if it points into our repo
        if [[ "$link_target" == "$REPO_DIR"* ]]; then
            local skill_name
            skill_name="$(basename "${target%/}")"
            rm "${target%/}"
            echo -e "  ${RED}REMOVED${NC} ${skill_name}"
            ((removed++)) || true
        fi
    done

    echo ""
    echo -e "Removed ${BOLD}${removed}${NC} symlink(s)."
}

# Show status of installed skills
show_status() {
    echo -e "${BOLD}Installed skills from this repo:${NC}"
    echo ""

    if [[ ! -d "$CLAUDE_SKILLS_DIR" ]]; then
        echo "Skills directory doesn't exist."
        exit 0
    fi

    local count=0
    for target in "$CLAUDE_SKILLS_DIR"/*/; do
        [[ ! -L "${target%/}" ]] && continue
        local link_target
        link_target="$(readlink "${target%/}" 2>/dev/null || echo "")"

        if [[ "$link_target" == "$REPO_DIR"* ]]; then
            local skill_name
            skill_name="$(basename "${target%/}")"
            local relative="${link_target#$REPO_DIR/}"
            echo -e "  ${GREEN}✓${NC} ${skill_name}  →  ${CYAN}${relative}${NC}"
            ((count++)) || true
        fi
    done

    echo ""
    echo -e "Total: ${BOLD}${count}${NC} skills linked from this repo."

    # Count non-repo skills
    local other=0
    for target in "$CLAUDE_SKILLS_DIR"/*/; do
        [[ -L "${target%/}" ]] && continue
        [[ -d "${target%/}" ]] && ((other++)) || true
    done
    if [[ $other -gt 0 ]]; then
        echo -e "Other: ${BOLD}${other}${NC} skills from other sources."
    fi
}

# List all available skills
list_skills() {
    echo -e "${BOLD}Available skills by domain:${NC}"
    echo ""

    local total=0
    for domain in "${DOMAINS[@]}"; do
        local count=0
        local skills=()
        while IFS= read -r domain_skill; do
            [[ -z "$domain_skill" ]] && continue
            skills+=("${domain_skill##*/}")
            ((count++)) || true
        done < <(find_skills_in_domain "$domain")

        echo -e "  ${BOLD}${domain}${NC} (${count})"
        for s in "${skills[@]}"; do
            echo -e "    ${s}"
        done
        echo ""
        total=$((total + count))
    done

    echo -e "Total: ${BOLD}${total}${NC} skills"
    exit 0
}

print_summary() {
    local dry_run="$1"
    echo "────────────────────────────────────"
    if [[ "$dry_run" == "true" ]]; then
        echo -e "  ${BOLD}DRY RUN SUMMARY${NC}"
    else
        echo -e "  ${BOLD}INSTALL SUMMARY${NC}"
    fi
    echo -e "  New:     ${GREEN}${installed}${NC}"
    echo -e "  Updated: ${BLUE}${updated}${NC}"
    echo -e "  Skipped: ${YELLOW}${skipped}${NC}"
    if [[ $failed -gt 0 ]]; then
        echo -e "  Failed:  ${RED}${failed}${NC}"
    fi
    echo "────────────────────────────────────"

    if [[ "$dry_run" != "true" && $installed -gt 0 ]]; then
        echo ""
        echo -e "Skills are now available globally in Claude Code."
        echo -e "Use ${CYAN}/skill-name${NC} or let Claude auto-detect them."
    fi
}

# Main
main() {
    local mode="install"
    local dry_run="false"
    local category=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)     dry_run="true"; shift ;;
            --uninstall)   mode="uninstall"; shift ;;
            --status)      mode="status"; shift ;;
            --list)        mode="list"; shift ;;
            --help|-h)     show_help ;;
            --category)
                mode="category"
                category="${2:-}"
                if [[ -z "$category" ]]; then
                    echo "Error: --category requires a domain name"
                    exit 1
                fi
                shift 2
                ;;
            *)
                echo "Unknown option: $1 (use --help for usage)"
                exit 1
                ;;
        esac
    done

    print_banner

    case $mode in
        install)
            install_domains "$dry_run" "${DOMAINS[@]}"
            print_summary "$dry_run"
            ;;
        category)
            install_domains "$dry_run" "$category"
            print_summary "$dry_run"
            ;;
        uninstall)
            uninstall_all
            ;;
        status)
            show_status
            ;;
        list)
            list_skills
            ;;
    esac
}

main "$@"

#!/usr/bin/env bash
set -euo pipefail

# Modh Agent Skills — Install Script
# Creates symlinks from this skill pack into a target project's .claude/skills/
# Works with: Claude Code, Cursor (Import Agent Skills), and any SKILL.md-compatible agent

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="$SCRIPT_DIR/skills"
TARGET_DIR="${1:-.}"  # Default to current directory

# Resolve absolute path
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Modh Agent Skills Installer${NC}"
echo "Source:  $SKILLS_DIR"
echo "Target:  $TARGET_DIR"
echo ""

# Tier definitions for --select mode
TIER_UNIVERSAL=(design-taste internal-tools-design output-enforcement cross-editor-setup)
TIER_REACT=(react-architecture nextjs-patterns shadcn-components)
TIER_BACKEND=(supabase-patterns observability webhook-architecture security-and-compliance testing)
TIER_PROCESS=(doc-audit feature-design linear-tickets pull-request ci-pipeline route-colocation)

# Parse flags
ALL_AGENTS=false
SELECT_MODE=false
SELECTED_TIERS=()

for arg in "$@"; do
  case "$arg" in
    --all-agents) ALL_AGENTS=true ;;
    --select) SELECT_MODE=true ;;
    --tier=*) SELECTED_TIERS+=("${arg#--tier=}") ;;
    --help|-h)
      echo "Usage: install.sh [target-dir] [options]"
      echo ""
      echo "Options:"
      echo "  --tier=universal   Install universal skills (any stack)"
      echo "  --tier=react       Install React/Next.js skills"
      echo "  --tier=backend     Install backend/infrastructure skills"
      echo "  --tier=process     Install workflow/process skills"
      echo "  --tier=all         Install all tiers (default)"
      echo "  --all-agents       Also generate Copilot + Windsurf config files"
      echo "  --help             Show this help"
      echo ""
      echo "Examples:"
      echo "  ./install.sh                         # Install all skills to current dir"
      echo "  ./install.sh ~/my-project            # Install to specific project"
      echo "  ./install.sh . --tier=universal --tier=react  # Only universal + React"
      echo "  ./install.sh . --all-agents          # Also generate Copilot/Windsurf files"
      exit 0
      ;;
  esac
done

# Determine which skills to install
SKILLS_TO_INSTALL=()

if [ ${#SELECTED_TIERS[@]} -eq 0 ]; then
  # Default: install all
  SELECTED_TIERS=(all)
fi

for tier in "${SELECTED_TIERS[@]}"; do
  case "$tier" in
    universal) SKILLS_TO_INSTALL+=("${TIER_UNIVERSAL[@]}") ;;
    react)     SKILLS_TO_INSTALL+=("${TIER_REACT[@]}") ;;
    backend)   SKILLS_TO_INSTALL+=("${TIER_BACKEND[@]}") ;;
    process)   SKILLS_TO_INSTALL+=("${TIER_PROCESS[@]}") ;;
    all)       SKILLS_TO_INSTALL+=("${TIER_UNIVERSAL[@]}" "${TIER_REACT[@]}" "${TIER_BACKEND[@]}" "${TIER_PROCESS[@]}") ;;
    *)         echo "Unknown tier: $tier"; exit 1 ;;
  esac
done

# Remove duplicates
SKILLS_TO_INSTALL=($(echo "${SKILLS_TO_INSTALL[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

# Step 1: Create .claude/skills/ if it doesn't exist
CLAUDE_SKILLS_DIR="$TARGET_DIR/.claude/skills"
mkdir -p "$CLAUDE_SKILLS_DIR"

# Step 2: Create symlinks for each skill
INSTALLED=0
SKIPPED=0

for skill in "${SKILLS_TO_INSTALL[@]}"; do
  SKILL_SOURCE="$SKILLS_DIR/$skill"
  SKILL_TARGET="$CLAUDE_SKILLS_DIR/$skill"

  if [ ! -d "$SKILL_SOURCE" ]; then
    echo -e "${YELLOW}  skip${NC} $skill (not found in pack)"
    ((SKIPPED++))
    continue
  fi

  if [ -L "$SKILL_TARGET" ]; then
    # Already a symlink — update it
    rm "$SKILL_TARGET"
  elif [ -d "$SKILL_TARGET" ]; then
    echo -e "${YELLOW}  skip${NC} $skill (local directory exists, not overwriting)"
    ((SKIPPED++))
    continue
  fi

  ln -s "$SKILL_SOURCE" "$SKILL_TARGET"
  echo -e "${GREEN}  link${NC} $skill"
  ((INSTALLED++))
done

echo ""
echo -e "${GREEN}Installed: $INSTALLED skills${NC}"
[ $SKIPPED -gt 0 ] && echo -e "${YELLOW}Skipped: $SKIPPED skills${NC}"

# Step 3: Create AGENTS.md if it doesn't exist
if [ ! -f "$TARGET_DIR/AGENTS.md" ]; then
  if [ -f "$SCRIPT_DIR/templates/nextjs-supabase.md" ]; then
    cp "$SCRIPT_DIR/templates/nextjs-supabase.md" "$TARGET_DIR/AGENTS.md"
    echo -e "${GREEN}  created${NC} AGENTS.md (from nextjs-supabase template)"
  fi
fi

# Step 4: Create CLAUDE.md if it doesn't exist
if [ ! -f "$TARGET_DIR/CLAUDE.md" ]; then
  echo "@AGENTS.md" > "$TARGET_DIR/CLAUDE.md"
  echo -e "${GREEN}  created${NC} CLAUDE.md (@AGENTS.md import)"
fi

# Step 5: Optional — generate configs for other agents
if [ "$ALL_AGENTS" = true ]; then
  # GitHub Copilot
  COPILOT_DIR="$TARGET_DIR/.github"
  mkdir -p "$COPILOT_DIR"
  if [ ! -f "$COPILOT_DIR/copilot-instructions.md" ] && [ -f "$TARGET_DIR/AGENTS.md" ]; then
    cp "$TARGET_DIR/AGENTS.md" "$COPILOT_DIR/copilot-instructions.md"
    echo -e "${GREEN}  created${NC} .github/copilot-instructions.md"
  fi

  # Windsurf
  if [ ! -f "$TARGET_DIR/.windsurfrules" ] && [ -f "$TARGET_DIR/AGENTS.md" ]; then
    cp "$TARGET_DIR/AGENTS.md" "$TARGET_DIR/.windsurfrules"
    echo -e "${GREEN}  created${NC} .windsurfrules"
  fi
fi

echo ""
echo -e "${BLUE}Done.${NC} Skills are linked and ready."
echo "  Claude Code: skills auto-discovered from .claude/skills/"
echo "  Cursor:      enable 'Import Agent Skills' in Settings > Rules"

#!/bin/bash

################################################################################
# n8n Quick Start Script
# Use this after setup.sh to easily manage n8n services
################################################################################

set -e

N8N_DIR="$HOME/n8n-stack"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}       n8n Management - Quick Start${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "1) Start services"
    echo "2) Stop services"
    echo "3) Restart services"
    echo "4) View status"
    echo "5) View logs"
    echo "6) Update n8n image"
    echo "7) Enter n8n container shell"
    echo "8) Database console"
    echo "9) Clean up & reset (⚠️  deletes data)"
    echo "0) Exit"
    echo ""
    read -p "Select option [0-9]: " choice
}

check_dir() {
    if [ ! -d "$N8N_DIR" ]; then
        echo -e "${RED}Error: n8n directory not found at $N8N_DIR${NC}"
        echo "Please run setup.sh first"
        exit 1
    fi
    cd "$N8N_DIR"
}

case_menu() {
    case $choice in
        1)
            check_dir
            echo -e "${BLUE}Starting n8n services...${NC}"
            docker-compose up -d
            echo -e "${GREEN}✓ Services started${NC}"
            echo ""
            docker-compose ps
            ;;
        2)
            check_dir
            echo -e "${BLUE}Stopping n8n services...${NC}"
            docker-compose down
            echo -e "${GREEN}✓ Services stopped${NC}"
            ;;
        3)
            check_dir
            echo -e "${BLUE}Restarting n8n services...${NC}"
            docker-compose restart
            echo -e "${GREEN}✓ Services restarted${NC}"
            sleep 2
            docker-compose ps
            ;;
        4)
            check_dir
            echo -e "${BLUE}Service Status:${NC}"
            echo ""
            docker-compose ps
            ;;
        5)
            check_dir
            echo -e "${BLUE}Showing logs (press Ctrl+C to exit)${NC}"
            echo ""
            docker-compose logs -f
            ;;
        6)
            check_dir
            echo -e "${BLUE}Updating n8n image...${NC}"
            docker-compose pull
            echo -e "${BLUE}Recreating containers...${NC}"
            docker-compose up -d
            echo -e "${GREEN}✓ n8n updated${NC}"
            ;;
        7)
            check_dir
            echo -e "${BLUE}Entering n8n container shell...${NC}"
            docker-compose exec n8n sh
            ;;
        8)
            check_dir
            echo -e "${BLUE}Connecting to PostgreSQL database...${NC}"
            docker-compose exec postgres psql -U n8n -d n8n
            ;;
        9)
            check_dir
            echo -e "${RED}⚠️  WARNING: This will delete all data!${NC}"
            read -p "Are you sure? Type 'yes' to confirm: " confirm
            if [ "$confirm" = "yes" ]; then
                echo -e "${BLUE}Removing all containers and volumes...${NC}"
                docker-compose down -v
                echo -e "${GREEN}✓ All data removed${NC}"
            else
                echo -e "${YELLOW}Cancelled${NC}"
            fi
            ;;
        0)
            echo -e "${BLUE}Goodbye!${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
    show_menu
}

# Main loop
while true; do
    show_menu
    case_menu
done

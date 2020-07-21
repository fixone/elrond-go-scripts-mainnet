#!/bin/bash
set -e

#Script version
VERSION="1.0.0"

#Color to the people
RED='\x1B[0;31m'
CYAN='\x1B[0;36m'
GREEN='\x1B[0;32m'
NC='\x1B[0m'

#Make script aware of its location
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

source $SCRIPTPATH/config/variables.cfg
source $SCRIPTPATH/config/functions.cfg

case "$1" in

'install')
  read -p "How many nodes do you want to run ? : " NUMBEROFNODES
  re='^[0-9]+$'
  if ! [[ $NUMBEROFNODES =~ $re ]] && [ "$NUMBEROFNODES" -gt 0 ]
  then
      NUMBEROFNODES = 1
  fi
  
  #Check if CUSTOM_HOME exists
  if ! [ -d "$CUSTOM_HOME" ]; then echo -e "${RED}Please configure your variables first ! (variables.cfg --> CUSTOM_HOME & CUSTOM_USER)${NC}"; exit; fi

  prerequisites
  replicant

  #Keep track of how many nodes you've started on the machine
  echo "$NUMBEROFNODES" > $CUSTOM_HOME/.numberofnodes
  paths
  go_lang
  #If repos are present and you run install again this will clean up for you :D
  if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then echo -e "${RED}--> Repos present. Either run the upgrade command or cleanup & install again...${NC}"; echo -e; exit; fi
  mkdir -p $GOPATH/src/github.com/ElrondNetwork
  git_clone
  build_node
  
  #Run the install process for each node
  for i in $(seq 1 $NUMBEROFNODES); 
        do 
         INDEX=$(( $i - 1 ))
         WORKDIR="$CUSTOM_HOME/elrond-nodes/node-$INDEX"
         install
         install_utils
         node_name
         keys
         systemd
       done
       
  sudo chown -R $CUSTOM_USER: $CUSTOM_HOME/elrond-nodes
  ;;

'upgrade')
  paths
  cd $GOPATH/src/github.com/ElrondNetwork/elrond-config-mainnet
  INSTALLED_CONFIGS=$(git status | grep HEAD | awk '{print $4}')
  echo -e
  echo -e "${GREEN}Local version for configs: ${CYAN}$INSTALLED_CONFIGS${NC}"
  echo -e
  echo -e "${GREEN}Github version of configs: ${CYAN}$CONFIGVER${NC}"
  echo -e
  
  echo -e 
  read -p "Do you want to go on with the upgrade (Default No) ? (Yy/Nn)" yn
  echo -e
  case $yn in
       [Yy]* )
         #Remove previously cloned repos
         if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then sudo rm -rf $GOPATH/src/github.com/ElrondNetwork/elrond-*; echo -e; echo -e "${RED}--> Repos present. Removing and fetching again...${NC}"; echo -e; fi
         git_clone
         build_node
         if ! [ -d "$CUSTOM_HOME/elrond-utils" ]; then mkdir -p $CUSTOM_HOME/elrond-utils; fi
         install_utils
  
         INSTALLEDNODES=$(cat $CUSTOM_HOME/.numberofnodes)
  
         #Run the update process for each node
         for i in $(seq 1 $INSTALLEDNODES);
             do
               UPDATEINDEX=$(( $i - 1 ))
               UPDATEWORKDIR="$CUSTOM_HOME/elrond-nodes/node-$UPDATEINDEX"
               cp -f $UPDATEWORKDIR/config/prefs.toml $UPDATEWORKDIR/config/prefs.toml.save
        
               sudo systemctl stop elrond-node-$UPDATEINDEX
               update
               mv $UPDATEWORKDIR/config/prefs.toml.save $UPDATEWORKDIR/config/prefs.toml
               sudo systemctl start elrond-node-$UPDATEINDEX
           done
        
            ;;
            
       [Nn]* )
          echo -e "${GREEN}Fine ! Skipping upgrade on this machine...${NC}"
            ;;
            
           * )
           echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
            ;;
      esac
  ;;

'start')
  NODESTOSTART=$(cat $CUSTOM_HOME/.numberofnodes)
  for i in $(seq 1 $NODESTOSTART);
      do
        STARTINDEX=$(( $i - 1 ))
        echo -e
        echo -e "${GREEN}Starting Elrond Node-$STARTINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
        echo -e
        sudo systemctl start elrond-node-$STARTINDEX
      done
  ;;

'stop')
  NODESTOSTOP=$(cat $CUSTOM_HOME/.numberofnodes)
  for i in $(seq 1 $NODESTOSTOP);
      do
        STOPINDEX=$(( $i - 1 ))
        echo -e
        echo -e "${GREEN}Stopping Elrond Node-$STOPINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
        echo -e
        sudo systemctl stop elrond-node-$STOPINDEX
      done
  ;;

'cleanup')
  paths
  echo -e 
  read -p "Do you want to delete installed nodes (Default No) ? (Yy/Nn)" yn
  echo -e
  case $yn in
       [Yy]* )
          echo -e "${RED}OK ! Cleaning everything !${NC}"
          
          if [[ -f $CUSTOM_HOME/.numberofnodes ]]; then
            NODESTODESTROY=$(cat $CUSTOM_HOME/.numberofnodes)
                for i in $(seq 1 $NODESTODESTROY);
                    do
                        KILLINDEX=$(( $i - 1 ))
                          echo -e
                          echo -e "${GREEN}Stopping Elrond Node-$KILLINDEX binary on host ${CYAN}$HOST${GREEN}...${NC}"
                          echo -e
                          if [ -e /etc/systemd/system/elrond-node-$KILLINDEX.service ]; then sudo systemctl stop elrond-node-$KILLINDEX; fi
                          echo -e "${GREEN}Erasing unit file and node folder for Elrond Node-$KILLINDEX...${NC}"
                          echo -e
                          if [ -e /etc/systemd/system/elrond-node-$KILLINDEX.service ]; then sudo rm /etc/systemd/system/elrond-node-$KILLINDEX.service; fi
                          if [ -d $CUSTOM_HOME/elrond-nodes/node-$KILLINDEX ]; then sudo rm -rf $CUSTOM_HOME/elrond-nodes/node-$KILLINDEX; fi
                    done
          fi

            #Reload systemd after deleting node units
            sudo systemctl daemon-reload
            
            echo -e
            echo -e "${GREEN}Removing elrond utils...${NC}"
            echo -e      
            
            if ps -all | grep -q termui; then killall termui; sleep 2; fi
            if [[ -e $CUSTOM_HOME/elrond-utils/termui ]]; then rm $CUSTOM_HOME/elrond-utils/termui; fi
              
            if ps -all | grep -q logviewer; then killall logviewer; sleep 2; fi
            if [[ -e $CUSTOM_HOME/elrond-utils/logviewer ]]; then rm $CUSTOM_HOME/elrond-utils/logviewer; fi
            
            rm -rf $CUSTOM_HOME/elrond-utils && rm -rf $CUSTOM_HOME/elrond-nodes
            
            echo -e "${GREEN}Removing paths from .profile on host ${CYAN}$HOST${GREEN}...${NC}"
            echo -e
            sed -i 'N;$!P;$!D;$d' ~/.profile
            
            echo -e "${GREEN}Removing cloned elrond-go & elrond-configs repo from host ${CYAN}$HOST${GREEN}...${NC}"
            echo -e      
            if [ -d "$GOPATH/src/github.com/ElrondNetwork/elrond-go" ]; then sudo rm -rf $GOPATH/src/github.com/ElrondNetwork/elrond-*; fi      
            ;;
            
       [Nn]* )
          echo -e "${GREEN}Fine ! Skipping cleanup on this machine...${NC}"
            ;;
            
           * )
           echo -e "${GREEN}I'll take that as a no then... moving on...${NC}"
            ;;
      esac
  ;;

'github_pull')
  #First backup identity, target_ips & variables.cfg
  if ! [ -d "$CUSTOM_HOME/script-configs-backup" ]; then mkdir -p $CUSTOM_HOME/script-configs-backup; fi
  
  echo -e
  echo -e "${GREEN}---> Backing up your existing configs (variables.cfg & identity)${NC}"
  echo -e
  cp -f $SCRIPTPATH/config/identity $CUSTOM_HOME/script-configs-backup
  cp -f $SCRIPTPATH/config/variables.cfg $CUSTOM_HOME/script-configs-backup
  
  echo -e "${GREEN}---> Fetching the latest version of the sripts...${NC}"
  echo -e
  
  #First let's check if the repo is accesible
  REPO_STATUS=$(curl -I "https://github.com/ElrondNetwork/elrond-go-scripts-mainnet" 2>&1 | awk '/HTTP\// {print $2}')
  cd $SCRIPTPATH
  if [ "$REPO_STATUS" -eq "200" ]; then
                                #Now let's fetch the latest version of the scripts
                                echo -e "${GREEN}---> elrond-go-scripts-mainnet is reachable ! Pulling latest version...${NC}"
                                git reset --hard HEAD
                                git pull
                      else echo -e "${RED}---> elrond-go-scripts-mainnet on Github not reachable !${NC}"
              fi
  #Restore configs after repo pull
  echo -e "${GREEN}---> Restoring your config files${NC}"
  echo -e
  cp -f $CUSTOM_HOME/script-configs-backup/* $SCRIPTPATH/config/
  replicant
  echo -e "${GREEN}---> Finished fetching scripts...${NC}"
  echo -e
  ;;

'get_logs')
  #Get journalctl logs from all the nodes
  NODELOGS=$(cat $CUSTOM_HOME/.numberofnodes)
  LOGSTIME=$(date "+%Y%m%d-%H%M")
  LOGSOFFSET=8080
  
  #Make sure the log path exists
  mkdir -p $CUSTOM_HOME/elrond-logs
  
  for i in $(seq 1 $NODELOGS);
      do
        LOGSINDEX=$(( $i - 1 ))
        LOGSAPIPORT=$(( $LOGSOFFSET + $LOGSINDEX ))
        echo -e
        echo -e "${GREEN}Getting logs for Elrond Node-$LOGSINDEX binary...${NC}"
        echo -e
        LOGSPUBLIC=$(curl -s http://127.0.0.1:$LOGSAPIPORT/node/status | jq -r .details.erd_public_key_block_sign | head -c 12)
        sudo journalctl --unit elrond-node-$LOGSINDEX >> $CUSTOM_HOME/elrond-logs/elrond-node-$LOGSINDEX-$LOGSPUBLIC.log
      done

  #Compress the logs and erase files
  cd $CUSTOM_HOME/elrond-logs/ && tar -zcvf elrond-node-logs-$LOGSTIME.tar.gz *.log && rm *.log  
  ;;

'version')
  echo -e
  echo -e "${GREEN}---> You are on version: ${CYAN}$VERSION${GREEN} of the scripts...${NC}"
  echo -e
  ;;

*)
  echo "Usage: Missing parameter ! [install|upgrade|start|stop|cleanup|get_logs|github_pull|version]"
  ;;
esac
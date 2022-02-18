#!/bin/bash                                                                                                                                                                                                                     
# Version 1.5
# Script to distribute files to a series of DX servers
# ARG1 = SourceFile full path
# ARG2 = Destination file full path
#
# Author: Eric Hart, LR TAM
# Date: 10/9/2020 - Created
# Date: 02/04/2022 - Updated to leverage /home/logrhythm/Soft/hosts 
#

SRCFILE=$1
DSTFILE=$2

if test -z $SRCFILE; then
  echo "Please provide a source argument.  Usage: copyfile_dxcluster.sh '/home/logrhythm/source.file' '/home/logrhythm/dest.file'"
  exit 1
fi

if test -z $DSTFILE; then
  echo "Please provide a destination argument.  Usage: copyfile_dxcluster.sh '/home/logrhythm/source.file' '/home/logrhythm/dest.file'"
  exit 1
fi

# Cluster Hot Nodes
declare -a CLSTR1H=()
declare -a CLSTR1HName=()

# Cluster Warm Nodes
declare -a CLSTR1W=()
declare -a CLSTR1WName=()

# Full Cluster
declare -a CLSTR1=()
declare -a CLSTR1Name=()

# Populate Command Menu system based on Hosts file
while IFS= read -r p; do
  IFS=' ' read v1 v2 v3 <<< "$p"
  if [[ "${v3,,}" == "hot"* ]]; then
    CLSTR1H+=($v1)
    CLSTR1HName+=($v2)
    CLSTR1+=($v1)
    CLSTR1Name+=($v2)
  fi

  if [[ "${v3,,}" == "warm"* ]]; then
    CLSTR1W+=($v1)
    CLSTR1WName+=($v2)
    CLSTR1+=($v1)
    CLSTR1Name+=($v2)
  fi
done < ./hosts

PS3="Which nodes would you like to run command:$COMMANDS on?"
options=("Hot Nodes" "Warm Nodes" "All Nodes" "Single Node" "Quit")
select opt in "${options[@]}"
do
  case $opt in
    "Hot Nodes")
      SNAMES=( "${CLSTR1HName[@]}" )
      SERVERS=( "${CLSTR1H[@]}" )
      break
      ;;
    "Warm Nodes")
      SNAMES=( "${CLSTR1WName[@]}" )
      SERVERS=( "${CLSTR1W[@]}" )
      break
      ;;
    "All Nodes")
      SNAMES=( "${CLSTR1Name[@]}" )
      SERVERS=( "${CLSTR1[@]}" )
      break
      ;;
    "Single Node")
      SNAMES=( "${CLSTR1HName[@]}" )
      SERVERS=( "${CLSTR1[@]}" )
      echo "-----------------------------------------------"
      echo "Server IPv4: "
      read SERVERS
      break
      ;;
    "Quit")
      break
     ;;
    *) echo "Invalid option: $REPLY";;
  esac
done

echo "Running command: $COMMANDS"
echo "On servers:  "
echo "Hostnames: ${SNAMES[*]}"
echo "IP Addresses: ${SERVERS[*]}"
echo ""
PS3="Would you like to proceed?"
options=("Yes" "No")
select opt in "${options[@]}"
do
  case $opt in
    "Yes")
      break
      ;;
    "No")
      exit 1
      ;;
    *) echo "Please enter: Yes or No";;
  esac
done

BLANK=""



for server in "${SERVERS[@]}"
do
  NOW=$(date)
  echo "$NOW - New Server Command Group: $server"
  echo "Copying file: $SRCFILE to $server:$DSTFILE"
  /usr/bin/rsync -avz -e "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no" $SRCFILE  logrhythm@$server:$DSTFILE
  echo "/usr/bin/rsync -avz -e "ssh -i ~/.ssh/id_rsa -o StrictHostKeyChecking=no" $SRCFILE  $DSTFILE"
  sleep .5
  NOW=$(date)
  echo "$NOW - End Server Command Group: $server"
done

exit 0;
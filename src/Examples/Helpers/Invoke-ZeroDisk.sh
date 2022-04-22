#!/bin/bash
# Name: Invoke-ZeroDisk.sh
# Purpose: Leveraging /dev/zero this script will write out in parallel multiple files containing all zeroes
#          for the potential benifit of permitting backend storage systems to recognize free blocks from a guest OS.
#
# Version: 1.0
# Date: 4/22/2022
# Author: Eric Hart
# Contact: Eric.Hart@logrhythm.com
#
echo "Invoke-ZeroDisk will perform concurrent dd commands to produce output files containing only zeroes from /dev/zero."
echo "Once the target filesystem path reaches 100% disk utilization the script will produce summary info showing the filesystem stats, "
echo "and perform a cleanup removing the written content, and produce a final summary of the filesystem stats."
echo ""
echo " Paths should be supplied as full paths without the ending /."
echo "   Example: /usr/local/logrhythm"
echo ""
read -p "Enter full path: " dpath
read -p "Number of files to produce: " fcount
echo "Zero-Write Begin"
for ((i=0; i<$fcount; i++))
do
  echo "Starting 'dd' thread#$i."
  sudo dd if=/dev/zero bs=8192 of=$dpath/zeroes_$i bs=8192 &
done
echo "Started $i Zero file threads.  Time to wait..."
wait
echo "Writing zeroes complete.  Posting metrics:"
ls -lha $dpath | grep zeroes
echo "----"
df -h
echo "Performing cleanup and deleting zero files..."
sudo rm -f $dpath/zeroes_*
echo "Cleanup complete.  Posting metrics:"
ls -lha $dpath | grep zeroes
echo "----"
df -h
echo ""
echo "Zero-Write Complete"

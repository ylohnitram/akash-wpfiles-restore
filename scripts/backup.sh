#!/bin/bash

# Check if another instance of script is running
pidof -o %PPID -x $0 >/dev/null && echo "ERROR: Script $0 already running" && exit 1

set -e

echo "Backing up WP files"

export AWS_ACCESS_KEY_ID=${BACKUP_KEY}
export AWS_SECRET_ACCESS_KEY=${BACKUP_SECRET}

mkdir -p /tmp/backup
rsync -cavz --stats -e "ssh -o StrictHostKeyChecking=no" root@${CMS_HOST}:/var/www/html/wp-content /tmp/backup
cd /tmp/backup
tar cvzf /tmp/wpf.tgz --owner=0 --group=0 --no-same-owner --no-same-permissions --warning=no-file-changed ./wp-content
#ssh -o stricthostkeychecking=no root@${CMS_HOST} "tar cvzf /tmp/wpf.tgz --owner=0 --group=0 --no-same-owner --no-same-permissions /var/www/html/wp-content"
#scp -o stricthostkeychecking=no root@${CMS_HOST}:/tmp/wpf.tgz .
#ssh -o stricthostkeychecking=no root@${CMS_HOST} "rm -f /tmp/wpf.tgz"

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
s3_uri_base="s3://${BACKUP_PATH}"
aws_args="--endpoint-url https://s3.filebase.com"

s3_uri="${s3_uri_base}/${CMS_DNS_A}_${timestamp}.tgz"

if [ -n "$BACKUP_PASSPHRASE" ]; then
  echo "Encrypting backup..."
  gpg --symmetric --batch --passphrase "${BACKUP_PASSPHRASE}" /tmp/wpf.tgz
  rm /tmp/wpf.tgz
  local_file="/tmp/wpf.tgz.gpg"
  s3_uri="${s3_uri}.gpg"
else
  local_file="/tmp/wpf.tgz"
  s3_uri="${s3_uri}"
fi

echo "Uploading backup to ${BACKUP_PATH}..."
aws ${aws_args} s3 cp "${local_file}" "${s3_uri}"
rm "${local_file}"

deleteAfter="${BACKUP_RETAIN:-"10 days"}"
echo "Deleting backups older than ${deleteAfter}"

aws ${aws_args} s3 ls "${s3_uri_base}/${CMS_DNS_A}" | while read -r line;  do
createDate=`echo $line|awk {'print $1" "$2'}`
createDate=`date -d"${createDate}" +%s`
olderThan=`date -d"-${deleteAfter}" +%s`
if [[ ${createDate} -lt ${olderThan} ]]
then
  fileName=`echo ${line} | awk '{$1=$2=$3=""; print $0}' | sed 's/^[ \t]*//'`
  if [[ "${fileName}" != "" ]]
  then
    aws ${aws_args} s3 rm "${s3_uri_base}/${fileName}"
  fi
fi
done;

echo "Backup complete."

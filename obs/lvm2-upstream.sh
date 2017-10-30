#!/bin/bash

#set -euE -o pipefail

OBS_DIR=/home/eric/suse/obs/home:ZRen:Upstream/lvm2
GIT_DIR=/home/eric/workspace/lvm2
BRANCH=latest

SOURCE=""
SIG=""

OLD_PWD=`pwd`

LOG=${OLD_PWD}/$(basename $0).log

API=https://api.opensuse.org

current_version=""
dm_current_version=""
latest_version=""
dm_latest_version=""

log_info()
{
	echo $* | tee -a "$LOG"
}

echo > "$LOG"

# check if $BRANCH exists
log_info "checking if $BRANCH exists..."
cd $GIT_DIR
git show-branch $BRANCH >>"$LOG" 2>&1 || {
		log_info "Creating branch \"$BRANCH\"..."
		git branch $BRANCH master >>"$LOG" 2>&1
	}

# update local repo
log_info "updating local repo..."
git checkout $BRANCH >>"$LOG" 2>&1
git fetch upstream master >>"$LOG" 2>&1
git merge upstream/master >>"$LOG" 2>&1

# get latest version
log_info "getting latest version..."
latest_version=$(cat VERSION | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')
dm_latest_version=$(cat VERSION_DM | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+')

# get latest tag version
f1=$(echo $latest_version | cut -d'.' -f1)
f2=$(echo $latest_version | cut -d'.' -f2)
f3=$(echo $latest_version | cut -d'.' -f3)
latest_version="$f1"."$f2"."$((f3 - 1))"

f1=$(echo $dm_latest_version | cut -d'.' -f1)
f2=$(echo $dm_latest_version | cut -d'.' -f2)
f3=$(echo $dm_latest_version | cut -d'.' -f3)
dm_latest_version="$f1"."$f2"."$((f3 - 1))"
log_info "latest LVM2 version: $latest_version"
log_info "latest DM version: $dm_latest_version"

cd $OBS_DIR
log_info "Cleaning OBS workspace..."
osc revert . >>"$LOG" 2>&1
osc clean >>"$LOG" 2>&1
osc -A "$API" update

log_info "get current version..."
current_version=$(cat lvm2.spec | grep "%define lvm2_version" | tr -s ' ' | cut -d' ' -f3)
dm_current_version=$(cat lvm2.spec | grep "%define device_mapper_version" | tr -s ' ' | cut -d' ' -f3)
log_info "current LVM2 version: $current_version"
log_info "current DM version: $dm_current_version"

if [ "$current_version" = "$latest_version" ] ; then
	log_info "The version doesn't change. Nothing to do!"
	exit 0
fi

sed -i -e "/%define lvm2_version/ s/$current_version/$latest_version/" lvm2.spec
sed -i -e "/%define device_mapper_version/ s/$dm_current_version/$dm_latest_version/" lvm2.spec

log_info "Downloading tarbar source..."
spectool --get-files --sources lvm2.spec >>"$LOG" 2>&1

SOURCE=LVM2."$latest_version".tgz
SIG="$SOURCE".asc
OLD_SOURCE=LVM2."$current_version".tgz
OLD_SIG="$OLD_SOURCE".asc

log_info "Checking if download successed..."
osc status | grep -E "^\?[[:space:]]+$SOURCE" >/dev/null 2>&1 || {
		log_info "$SOURCE not downloaded?"	
		exit 1
	}
osc status | grep -E "^\?[[:space:]]+$SIG" >/dev/null 2>&1 || {
		log_info "$SIG not downloaded?"	
		exit 1
	}

log_info "Checking PGP signature..."
gpg --verify "$SIG" "$SOURCE" 2>&1 | grep "gpg: CRC error" && {
		log_info "Checksume failed."
		exit 1
	}

log_info "Removing $OLD_SOURCE $OLD_SIG"
rm -f "$OLD_SOURCE"
rm -f "$OLD_SIG"

MSG="Update to LVM2.$latest_version"
osc vc -m "$MSG" lvm2.changes

osc addremove >>"$LOG" 2>&1

chmod u+x pre_checkin.sh
./pre_checkin.sh

osc -A "$API" ci -m "$MSG" >>"$LOG" 2>&1

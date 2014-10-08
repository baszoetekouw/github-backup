#!/bin/bash
# A simple script to backup an organization's GitHub repositories.

# all of the following can be overriden by env variables:

# where to place the backup files
GHBU_BACKUP_DIR=${GHBU_BACKUP_DIR:-"github-backups"}
# type (org for organisation or user for user) of github repos to backup
GHBU_TYPE=${GHBU_TYPE:-org}
# the GitHub organization whose repos will be backed up
# (if you're backing up a user's repos instead, this should be your GitHub username)
GHBU_ORG=${GHBU_ORG:-"<CHANGE-ME>"}
# the username of a GitHub account (to use with the GitHub API)
# Instead of a username, yo can also put in an OAuth access key here
GHBU_UNAME=${GHBU_UNAME:-"<CHANGE-ME>"}
# the password for that account (or empty if an OAuth access key is used)
GHBU_PASSWD=${GHBU_PASSWD:-}

# when `true`, old backups will be deleted
GHBU_PRUNE_OLD=${GHBU_PRUNE_OLD:-true}
# the min age (in days) of backup files to delete
GHBU_PRUNE_AFTER_N_DAYS=${GHBU_PRUNE_AFTER_N_DAYS:-7}
# when `true`, only show error messages
GHBU_SILENT=${GHBU_SILENT:-false}

# the GitHub hostname
GHBU_GITHOST="github.com"
# base URI for the GitHub API
GHBU_API=${GHBU_API:-"https://api.github.com"}
# base command to use to clone GitHub repos
GHBU_GIT_CLONE_CMD="git clone --quiet --mirror https://${GHBU_UNAME}:${GHBU_PASSWD}@${GHBU_GITHOST}/"

TSTAMP=`date "+%Y-%m-%dT%H:%M%z"`

# The function `check` will exit the script if the given command fails.
function check {
	"$@"
	status=$?
	if [ $status -ne 0 ]; then
		echo "ERROR: Encountered error (${status}) while running the following:" >&2
		echo "           $@"  >&2
		echo "       (at line ${BASH_LINENO[0]} of file $0.)"  >&2
		echo "       Aborting." >&2
		exit $status
	fi
}

# The function `tgz` will create a gzipped tar archive of the specified file ($1) and then remove the original
function tgz {
	check tar zcf $1.tar.gz $1 && check rm -rf $1
}

$GHBU_SILENT || (echo "" && echo "=== INITIALIZING ===" && echo "")

$GHBU_SILENT || echo "Using backup directory $GHBU_BACKUP_DIR"
check mkdir -p $GHBU_BACKUP_DIR

$GHBU_SILENT || echo -n "Fetching list of repositories for ${GHBU_ORG}..."

REPOLIST=$(
	  check curl --silent -u $GHBU_UNAME:$GHBU_PASSWD ${GHBU_API}/${GHBU_TYPE}s/${GHBU_ORG}/repos -q \
	| check grep '"name"' \
	| check awk -F': "' '{print $2}' \
	| check sed -e 's/",//g'
)

if ! $GHBU_SILENT
then
	echo "found $(echo $REPOLIST | wc -w) repositories."
	echo "" && echo "=== BACKING UP ===" && echo ""
fi

for REPO in $REPOLIST
do
	$GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO}"
	check ${GHBU_GIT_CLONE_CMD}${GHBU_ORG}/${REPO}.git \
		${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}-${TSTAMP}.git \
		&& tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}-${TSTAMP}.git

	$GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO}.wiki (if any)"
	${GHBU_GIT_CLONE_CMD}${GHBU_ORG}/${REPO}.wiki.git \
		${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.wiki-${TSTAMP}.git 2>/dev/null \
		&& tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.wiki-${TSTAMP}.git

	$GHBU_SILENT || echo "Backing up ${GHBU_ORG}/${REPO} issues"
	check curl --silent -u $GHBU_UNAME:$GHBU_PASSWD \
		${GHBU_API}/repos/${GHBU_ORG}/${REPO}/issues \
		-q > ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.issues-${TSTAMP} \
		&& tgz ${GHBU_BACKUP_DIR}/${GHBU_ORG}-${REPO}.issues-${TSTAMP}
done

if $GHBU_PRUNE_OLD
then
	if ! $GHBU_SILENT
	then
		echo "" && echo "=== PRUNING ===" && echo ""
		echo "Pruning backup files ${GHBU_PRUNE_AFTER_N_DAYS} days old or older."
		N=$(find $GHBU_BACKUP_DIR -name '*.tar.gz' -mtime +$GHBU_PRUNE_AFTER_N_DAYS | wc -l)
		echo "Found $N files to prune."
	fi
	find $GHBU_BACKUP_DIR -name '*.tar.gz' -mtime +$GHBU_PRUNE_AFTER_N_DAYS -exec rm -fv {} > /dev/null \;
fi

if ! $GHBU_SILENT
then
	echo "" && echo "=== DONE ===" && echo ""
	echo "GitHub backup completed." && echo ""
fi


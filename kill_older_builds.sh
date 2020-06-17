#!/bin/bash
# This script stops CodeBuild builds that are associated with previous git commit on the same branch
# It prevents CodeBuild from deploying older version of the code

set -e

while getopts r:p:c: option
do
case "${option}"
in
r) AWS_REGION=${OPTARG};;
p) CODEBUILD_PROJECT_NAME=${OPTARG};;
c) PREVIOUS_COMMIT_ID=${OPTARG};;
esac
done

if [ -z "$AWS_REGION" ]; then
    echo "exit: No AWS_REGION specified (-r parameter)"
    exit 1;
fi

if [ -z "$CODEBUILD_PROJECT_NAME" ]; then
    echo "exit: No CODEBUILD_PROJECT_NAME specified (-p parameter)"
    exit 1;
fi

if [ -z "$PREVIOUS_COMMIT_ID" ]; then
    echo "exit: No PREVIOUS_COMMIT_ID specified (-c parameter)"
    exit 1;
fi

echo "AWS_REGION: " $AWS_REGION
echo "CODE_BUILD_PROJECT_NAME: " $CODE_BUILD_PROJECT_NAME
echo "PREVIOUS_COMMIT_ID: " $PREVIOUS_COMMIT_ID

# Get most recent build IDs
BUILD_IDS=$(aws --region $AWS_REGION --profile tslkd codebuild list-builds-for-project --project-name $CODEBUILD_PROJECT_NAME --sort-order DESCENDING | jq -r '.ids[]')

# Fetch more details for these builds
BUILD_LIST=$(aws --region $AWS_REGION --profile tslkd codebuild batch-get-builds --ids $BUILD_IDS)

# Iterate each build and determine if one one of them are outdated and need to be stopped
for row in $(echo "${BUILD_LIST}" | jq -r '.builds[] | @base64'); do
    _jq() {
     echo ${row} | base64 --decode | jq -r ${1}
    }
    BUILD_ID=$(_jq '.id')
    BUILD_STATUS=$(_jq '.currentPhase')
    SOURCE_VERSION=$(_jq '.sourceVersion')
    if [ "$BUILD_STATUS" != "COMPLETED" ] && [ "$SOURCE_VERSION" == "$PREVIOUS_COMMIT_ID" ]; then
      echo "Build for the previous commit is still in progress! Build ID: $BUILD_ID"
      echo "Attempting to stop the older build..."
      aws --region $AWS_REGION --profile tslkd codebuild stop-build --id $BUILD_ID
    fi
done

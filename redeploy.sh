#!/bin/bash
# This script redeploys ECS services with new Docker image version (modified version based on https://serverfault.com/a/807447/241403)
# Get the name of task definition
TASK_DEFINITION_NAME=$(aws ecs describe-services --profile $AWS_DEFAULT_PROFILE --region $AWS_DEFAULT_REGION --services $ECS_SERVICE_NAME --cluster $ECS_CLUSTER_NAME | jq -r .services[0].taskDefinition)
echo "Current task definition name: $TASK_DEFINITION_NAME"
# Get the task definition itself
TASK_DEFINITION=$(aws ecs describe-task-definition --profile $AWS_DEFAULT_PROFILE --region $AWS_DEFAULT_REGION --task-def "$TASK_DEFINITION_NAME" | jq '.taskDefinition')
# Make sure we have only 1 container definition in this task, as this script only supports 1 at this time
NUMBER_OF_CONTAINER_DEFINITIONS=$(echo $TASK_DEFINITION | jq '.containerDefinitions | length')
if (( $NUMBER_OF_CONTAINER_DEFINITIONS != 1 )); then
    echo "Error: this deployment script supports only tasks with one container definition!";
    exit 1;
fi
# Change image in the container definition to point to another tag in our Docker repository
TASK_DEFINITION=$(echo $TASK_DEFINITION | jq ".containerDefinitions[0].image = \"$NEW_IMAGE_URL\"")
# Leave only the properties that AWS expects to get back in "register-task-definition" function call (as of 2020-06-16). If new properties will be added by AWS, script will need to be updated. Otherwise it will remove the properties from the task definition.
# Good way to get a list of supported properties is to send a request with an invalid property. Error message includes a list of supported properties.
TASK_DEFINITION=$(echo $TASK_DEFINITION | jq '{family: .family, taskRoleArn: .taskRoleArn, executionRoleArn: .executionRoleArn, networkMode: .networkMode, containerDefinitions: .containerDefinitions, volumes: .volumes, placementConstraints: .placementConstraints, requestCompatibilities: .requesCompatibilities, cpu: .cpu, memory: .memory, tags: .tags, pidMode: .pidMode, ipcMode: .ipcMode, proxyConfiguration: .proxyConfiguration, inferenceAccelerators: .inferenceAccelerators}')
# Remove properties with null values
TASK_DEFINITION=$(echo $TASK_DEFINITION | jq 'del(.[] | nulls)')
# Deploy the updated task definition and retrieve its ARN
TASK_ARN=`aws ecs register-task-definition --profile $AWS_DEFAULT_PROFILE --region $AWS_DEFAULT_REGION --cli-input-json "$TASK_DEFINITION" | jq -r .taskDefinition.taskDefinitionArn`
echo "New task definition registered, $TASK_ARN"
# Force new deployment of the ECS service (with updated task definition)
aws ecs update-service --profile $AWS_DEFAULT_PROFILE --region $AWS_DEFAULT_REGION --cluster $ECS_CLUSTER_NAME --service $ECS_SERVICE_NAME --task-definition "$TASK_ARN"
echo "Service updated"

# ecs-101-demo

This is a small demo application for an ECS 101 talk that I gave @ AWSMeetupGroup. [Here is the recorded video of the talk](https://www.youtube.com/watch?v=pOvV0FypJA0&t=19s).

## Repo Contents

1. The Demo Application code resides in `app/` and was originally copied from [awesome-compose](https://github.com/docker/awesome-compose), specifically the [React, Express, Mongo example](https://github.com/docker/awesome-compose/tree/master/react-express-mongodb). It has been slightly adapted for this example.
1. The Infrastructure as Code for this example has been written in Terraform and resides in `terraform/`.
1. The Task Definitions for the 3 services have been pulled down and shared in `task_definitions/`.

## Deploying to AWS yourself

### Prequisites

1. [Terraform v0.12.25](https://github.com/tfutils/tfenv)
1. [Docker](https://docs.docker.com/get-docker/) + [Compose](https://docs.docker.com/compose/install/)
1. An AWS Account + AWS IAM Credentials

### Instructions

Execute the following commands and tasks to spin up this ECS project in your own AWS account:

1. `cd ./terraform`
1. Update `root.auto.tfvars` with your own values
1. `terraform init`
1. `terraform plan -out=run.plan`
   1. Check out this commands plan output to make sure it fits what you want to deploy
1. `terraform apply run.plan`
1. Repeat the previous two steps until you don't have any apply errors (Terraform typically ain't perfect 😅)
1. Copy down the two ECR endpoints that Terraform outputs
   1. `export FRONTEND_ECR_URL=$(terraform output frontend_repo_url)`
   1. `export BACKEND_ECR_URL=$(terraform output backend_repo_url)`
1. Build and push the Frontend image:
   1. `cd ../app/frontend`
   1. `docker build -tag $FRONTEND_ECR_URL:latest .`
   1. `docker push $FRONTEND_ECR_URL`
1. Build and push the Backend image:
   1. `cd ../app/backend`
   1. `docker build -tag $BACKEND_ECR_URL:latest .`
   1. `docker push $BACKEND_ECR_URL`
1. Sign into the AWS console and check out the app running in ECS!
1. Your app should also be running @ `ecs101.${var.domain}`


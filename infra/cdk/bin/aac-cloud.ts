#!/usr/bin/env node
import * as cdk from "aws-cdk-lib";
import { AacCloudStack } from "../lib/aac-cloud-stack";

const app = new cdk.App();
const stage = app.node.tryGetContext("stage") ?? "dev";

new AacCloudStack(app, `AacCloud-${stage}`, {
  description: `AAC cloud stack (${stage})`,
  stage,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION ?? "eu-central-1",
  },
});

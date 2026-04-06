import * as cdk from "aws-cdk-lib";
import { Construct } from "constructs";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as iam from "aws-cdk-lib/aws-iam";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as apigwv2 from "aws-cdk-lib/aws-apigatewayv2";
import * as apigwv2Auth from "aws-cdk-lib/aws-apigatewayv2-authorizers";
import * as apigwv2Integrations from "aws-cdk-lib/aws-apigatewayv2-integrations";
import * as iot from "aws-cdk-lib/aws-iot";
import * as path from "node:path";

export interface AacCloudStackProps extends cdk.StackProps {
  stage: string;
}

export class AacCloudStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: AacCloudStackProps) {
    super(scope, id, props);
    const stage = props.stage;
    const prefix = `aac-${stage}`;

    const iotDataEndpointParam = new cdk.CfnParameter(this, "IotDataEndpoint", {
      type: "String",
      description: "AWS IoT Data endpoint (ats). Example: <prefix>-ats.iot.<region>.amazonaws.com",
    });
    const provisioningRoleArnParam = new cdk.CfnParameter(this, "ProvisioningRoleArn", {
      type: "String",
      description: "IAM role ARN used by IoT Fleet Provisioning template.",
    });
    const callbackUrlsParam = new cdk.CfnParameter(this, "CognitoCallbackUrls", {
      type: "CommaDelimitedList",
      description: "Allowed callback URLs for Cognito App Client.",
      default: "com.koray.artaircleaner://callback",
    });
    const signoutUrlsParam = new cdk.CfnParameter(this, "CognitoSignoutUrls", {
      type: "CommaDelimitedList",
      description: "Allowed signout URLs for Cognito App Client.",
      default: "com.koray.artaircleaner://callback",
    });

    const ownershipTable = new dynamodb.Table(this, "OwnershipTable", {
      tableName: `${prefix}-device-ownership`,
      partitionKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    ownershipTable.addGlobalSecondaryIndex({
      indexName: "byOwnerUserId",
      partitionKey: { name: "ownerUserId", type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const stateTable = new dynamodb.Table(this, "StateTable", {
      tableName: `${prefix}-device-state`,
      partitionKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const userDevicesTable = new dynamodb.Table(this, "UserDevicesTable", {
      tableName: `${prefix}-user-devices`,
      partitionKey: { name: "userId", type: dynamodb.AttributeType.STRING },
      sortKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
    userDevicesTable.addGlobalSecondaryIndex({
      indexName: "byDeviceId",
      partitionKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      sortKey: { name: "userId", type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const invitesTable = new dynamodb.Table(this, "InvitesTable", {
      tableName: `${prefix}-device-invites`,
      partitionKey: { name: "inviteId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      timeToLiveAttribute: "expiresAt",
    });
    invitesTable.addGlobalSecondaryIndex({
      indexName: "byDeviceId",
      partitionKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      sortKey: { name: "createdAt", type: dynamodb.AttributeType.NUMBER },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const integrationLinksTable = new dynamodb.Table(this, "IntegrationLinksTable", {
      tableName: `${prefix}-integration-links`,
      partitionKey: { name: "integrationId", type: dynamodb.AttributeType.STRING },
      sortKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      timeToLiveAttribute: "expiresAt",
    });
    integrationLinksTable.addGlobalSecondaryIndex({
      indexName: "byDeviceId",
      partitionKey: { name: "deviceId", type: dynamodb.AttributeType.STRING },
      sortKey: { name: "integrationId", type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    const cmdIdempotencyTable = new dynamodb.Table(this, "CmdIdempotencyTable", {
      tableName: `${prefix}-cmd-idempotency`,
      partitionKey: { name: "cmdKey", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      timeToLiveAttribute: "expiresAt",
    });

    const auditTable = new dynamodb.Table(this, "AuditTable", {
      tableName: `${prefix}-audit`,
      partitionKey: { name: "auditId", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      timeToLiveAttribute: "expiresAt",
    });

    const rateLimitTable = new dynamodb.Table(this, "RateLimitTable", {
      tableName: `${prefix}-rate-limit`,
      partitionKey: { name: "rateKey", type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      timeToLiveAttribute: "expiresAt",
    });

    const iotStateIngestRole = new iam.Role(this, "IotStateIngestRole", {
      assumedBy: new iam.ServicePrincipal("iot.amazonaws.com"),
    });
    stateTable.grantWriteData(iotStateIngestRole);

    new iot.CfnTopicRule(this, "DeviceShadowToStateRule", {
      ruleName: `${prefix.replace(/-/g, "_")}_shadow_to_state`,
      topicRulePayload: {
        sql: "SELECT topic(2) as deviceId, encode(*, 'base64') as payload_b64, timestamp() as updatedAt FROM 'aac/+/shadow'",
        awsIotSqlVersion: "2016-03-23",
        actions: [
          {
            dynamoDBv2: {
              roleArn: iotStateIngestRole.roleArn,
              putItem: {
                tableName: stateTable.tableName,
              },
            },
          },
        ],
        ruleDisabled: false,
      },
    });

    const otaBucket = new s3.Bucket(this, "OtaArtifactsBucket", {
      bucketName: `${prefix}-ota-artifacts-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      autoDeleteObjects: false,
    });

    const userPool = new cognito.UserPool(this, "UserPool", {
      userPoolName: `${prefix}-users`,
      signInAliases: { email: true },
      selfSignUpEnabled: true,
      standardAttributes: {
        email: { required: true, mutable: true },
      },
      passwordPolicy: {
        minLength: 10,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      mfa: cognito.Mfa.OPTIONAL,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const appClient = userPool.addClient("AppClient", {
      userPoolClientName: `${prefix}-flutter-client`,
      authFlows: {
        userSrp: true,
        userPassword: false,
      },
      oAuth: {
        flows: { authorizationCodeGrant: true },
        callbackUrls: callbackUrlsParam.valueAsList,
        logoutUrls: signoutUrlsParam.valueAsList,
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
      },
      generateSecret: false,
      preventUserExistenceErrors: true,
      accessTokenValidity: cdk.Duration.minutes(60),
      idTokenValidity: cdk.Duration.minutes(60),
      refreshTokenValidity: cdk.Duration.days(30),
    });

    const domainPrefix = `${prefix}-${cdk.Aws.ACCOUNT_ID}`.slice(0, 63);
    const userPoolDomain = userPool.addDomain("HostedUiDomain", {
      cognitoDomain: { domainPrefix },
    });

    const lambdaFn = new lambda.Function(this, "CloudApiLambda", {
      functionName: `${prefix}-cloud-api`,
      runtime: lambda.Runtime.NODEJS_18_X,
      architecture: lambda.Architecture.ARM_64,
      handler: "aac-cloud-api.handler",
      timeout: cdk.Duration.seconds(29),
      memorySize: 512,
      code: lambda.Code.fromAsset(path.join(__dirname, "../../../../scripts/aws")),
      environment: {
        OWNERSHIP_TABLE: ownershipTable.tableName,
        STATE_TABLE: stateTable.tableName,
        USER_DEVICES_TABLE: userDevicesTable.tableName,
        INVITES_TABLE: invitesTable.tableName,
        INTEGRATION_LINKS_TABLE: integrationLinksTable.tableName,
        OWNERSHIP_BY_OWNER_GSI: "byOwnerUserId",
        USER_DEVICES_BY_DEVICE_GSI: "byDeviceId",
        INVITES_BY_DEVICE_GSI: "byDeviceId",
        INTEGRATION_LINKS_BY_DEVICE_GSI: "byDeviceId",
        CMD_IDEMPOTENCY_TABLE: cmdIdempotencyTable.tableName,
        AUDIT_TABLE: auditTable.tableName,
        RATE_LIMIT_TABLE: rateLimitTable.tableName,
        IOT_ENDPOINT: iotDataEndpointParam.valueAsString,
        FEATURE_INVITES: "1",
        FEATURE_RATE_LIMIT: "1",
        CLAIM_PROOF_SYNC_RATE_LIMIT_WINDOW_SEC: "60",
        CLAIM_PROOF_SYNC_RATE_LIMIT_MAX: "6",
        FEATURE_IDEMPOTENCY: "1",
        FEATURE_CLAIM_PROOF: "1",
        FEATURE_SHADOW_STATE: "1",
        FEATURE_SHADOW_DESIRED: "1",
        FEATURE_SHADOW_ACL_SYNC: "1",
        FEATURE_OTA_JOBS: "1",
        THING_NAME_PREFIX: "aac-",
        IOT_THING_ARN_PREFIX: `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:thing/`,
        AWS_ACCOUNT_ID: cdk.Aws.ACCOUNT_ID,
      },
    });

    ownershipTable.grantReadWriteData(lambdaFn);
    stateTable.grantReadWriteData(lambdaFn);
    userDevicesTable.grantReadWriteData(lambdaFn);
    invitesTable.grantReadWriteData(lambdaFn);
    integrationLinksTable.grantReadWriteData(lambdaFn);
    cmdIdempotencyTable.grantReadWriteData(lambdaFn);
    auditTable.grantReadWriteData(lambdaFn);
    rateLimitTable.grantReadWriteData(lambdaFn);
    otaBucket.grantRead(lambdaFn);

    lambdaFn.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "IotDataPlane",
        actions: [
          "iot:Publish",
          "iot:GetThingShadow",
          "iot:UpdateThingShadow",
        ],
        resources: [
          `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/aac/*/cmd`,
          `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:thing/aac-*`,
        ],
      }),
    );

    lambdaFn.addToRolePolicy(
      new iam.PolicyStatement({
        sid: "IotJobsControlPlane",
        actions: ["iot:CreateJob", "iot:DescribeJob", "iot:CancelJob", "iot:DescribeThing"],
        resources: [
          `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:job/*`,
          `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:thing/aac-*`,
          `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:thing/??????`,
        ],
      }),
    );

    const httpApi = new apigwv2.HttpApi(this, "HttpApi", {
      apiName: `${prefix}-http-api`,
      corsPreflight: {
        allowHeaders: ["authorization", "content-type"],
        allowMethods: [apigwv2.CorsHttpMethod.GET, apigwv2.CorsHttpMethod.POST, apigwv2.CorsHttpMethod.OPTIONS],
        allowOrigins: ["*"],
        maxAge: cdk.Duration.days(7),
      },
    });

    const integration = new apigwv2Integrations.HttpLambdaIntegration("CloudApiIntegration", lambdaFn);
    const jwtAuthorizer = new apigwv2Auth.HttpJwtAuthorizer("JwtAuth", userPool.userPoolProviderUrl, {
      jwtAudience: [appClient.userPoolClientId],
    });

    httpApi.addRoutes({
      path: "/health",
      methods: [apigwv2.HttpMethod.GET],
      integration,
    });
    httpApi.addRoutes({
      path: "/healthz",
      methods: [apigwv2.HttpMethod.GET],
      integration,
    });

    const authedRoutes: Array<{ path: string; methods: apigwv2.HttpMethod[] }> = [
      { path: "/me", methods: [apigwv2.HttpMethod.GET] },
      { path: "/me/invites", methods: [apigwv2.HttpMethod.GET] },
      { path: "/devices", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/claim", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/name", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/claim/recover", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/claim-proof/sync", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/capabilities", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/ha/config", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/state", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/cmd", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/desired", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/ota/job", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/invite", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/invites", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/members", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/acl/push", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/integration/link", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/integrations", methods: [apigwv2.HttpMethod.GET] },
      { path: "/device/{id6}/integration/{integrationId}/revoke", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/invite/{inviteId}/revoke", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/member/{userSub}/revoke", methods: [apigwv2.HttpMethod.POST] },
      { path: "/device/{id6}/unclaim", methods: [apigwv2.HttpMethod.POST] },
    ];
    for (const r of authedRoutes) {
      httpApi.addRoutes({
        path: r.path,
        methods: r.methods,
        integration,
        authorizer: jwtAuthorizer,
      });
    }

    const claimPolicy = new iot.CfnPolicy(this, "ClaimCertPolicy", {
      policyName: `${prefix}-claim-cert`,
      policyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Action: ["iot:Connect"],
            Resource: `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:client/claim-*`,
          },
          {
            Effect: "Allow",
            Action: ["iot:Publish", "iot:Receive"],
            Resource: [
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/$aws/certificates/create/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/$aws/certificates/create-from-csr/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/$aws/provisioning-templates/*`,
            ],
          },
          {
            Effect: "Allow",
            Action: ["iot:Subscribe"],
            Resource: [
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/certificates/create/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/certificates/create-from-csr/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/provisioning-templates/*`,
            ],
          },
        ],
      },
    });

    const thingPolicy = new iot.CfnPolicy(this, "ThingPolicy", {
      policyName: `${prefix}-thing`,
      policyDocument: {
        Version: "2012-10-17",
        Statement: [
          {
            Effect: "Allow",
            Action: ["iot:Connect"],
            Resource: `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:client/\${iot:Connection.Thing.ThingName}`,
          },
          {
            Effect: "Allow",
            Action: ["iot:Publish", "iot:Receive"],
            Resource: [
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/aac/\${iot:Connection.Thing.Attributes[id6]}/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topic/$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*`,
            ],
          },
          {
            Effect: "Allow",
            Action: ["iot:Subscribe"],
            Resource: [
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/aac/\${iot:Connection.Thing.Attributes[id6]}/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/things/\${iot:Connection.Thing.ThingName}/shadow/*`,
              `arn:${cdk.Aws.PARTITION}:iot:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:topicfilter/$aws/things/\${iot:Connection.Thing.ThingName}/jobs/*`,
            ],
          },
        ],
      },
    });

    new iot.CfnProvisioningTemplate(this, "FleetProvisioningTemplate", {
      enabled: true,
      provisioningRoleArn: provisioningRoleArnParam.valueAsString,
      templateName: `${prefix}-fleet-provisioning`,
      description: "Provision AAC thing/cert and attach least-privilege thing policy.",
      templateBody: JSON.stringify({
        Parameters: {
          SerialNumber: { Type: "String" },
          Id6: { Type: "String" },
        },
        Resources: {
          thing: {
            Type: "AWS::IoT::Thing",
            Properties: {
              ThingName: {
                "Fn::Join": ["", ["aac-", { Ref: "Id6" }]],
              },
              AttributePayload: {
                id6: { Ref: "Id6" },
                serialNumber: { Ref: "SerialNumber" },
              },
            },
          },
          certificate: {
            Type: "AWS::IoT::Certificate",
            Properties: {
              CertificateId: { Ref: "AWS::IoT::Certificate::Id" },
              Status: "ACTIVE",
            },
          },
          policy: {
            Type: "AWS::IoT::Policy",
            Properties: {
              PolicyName: thingPolicy.policyName,
            },
          },
        },
      }),
    });

    new cdk.CfnOutput(this, "HttpApiUrl", { value: httpApi.apiEndpoint });
    new cdk.CfnOutput(this, "CognitoUserPoolId", { value: userPool.userPoolId });
    new cdk.CfnOutput(this, "CognitoClientId", { value: appClient.userPoolClientId });
    new cdk.CfnOutput(this, "CognitoIssuer", { value: userPool.userPoolProviderUrl });
    new cdk.CfnOutput(this, "CognitoHostedDomainUrl", {
      value: `https://${userPoolDomain.domainName}.auth.${this.region}.amazoncognito.com`,
    });
    new cdk.CfnOutput(this, "OtaBucketName", { value: otaBucket.bucketName });
    new cdk.CfnOutput(this, "ClaimPolicyName", { value: claimPolicy.policyName ?? "" });
    new cdk.CfnOutput(this, "ThingPolicyName", { value: thingPolicy.policyName ?? "" });
  }
}

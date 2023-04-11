const {
  SchemasClient,
  ListSchemasCommand,
  DescribeSchemaCommand,
} = require("@aws-sdk/client-schemas");
const { SNSClient, PublishCommand } = require("@aws-sdk/client-sns");
const jsonschema = require("jsonschema").Validator;
const { OpenApiValidator } = require("express-openapi-validator");

const schemasClient = new SchemasClient();
const snsClient = new SNSClient();

let schemasCache = null;

async function getSchemas() {
  if (schemasCache) {
    return schemasCache;
  }

  const registryArn = process.env.SCHEMA_REGISTRY_ARN;
  const registryName = registryArn.split("/").pop();
  const schemas = [];

  let nextToken = null;
  do {
    const response = await schemasClient.send(
      new ListSchemasCommand({
        RegistryName: registryName,
        NextToken: nextToken,
      })
    );

    for (const schema of response.Schemas) {
      const schemaDefinition = await schemasClient.send(
        new DescribeSchemaCommand({
          RegistryName: registryName,
          SchemaName: schema.SchemaName,
        })
      );
      schemas.push(JSON.parse(schemaDefinition.Content));
    }

    nextToken = response.NextToken;
  } while (nextToken);

  schemasCache = schemas;
  return schemas;
}

async function validateEvent(event, schema) {
  if (schema.openapi) {
    const openApiValidator = new OpenApiValidator({
      apiSpec: schema,
    });
    try {
      await openApiValidator.validate(event);
      return true;
    } catch (error) {
      return false;
    }
  } else {
    const validator = new jsonschema();
    return validator.validate(event, schema).valid;
  }
}

exports.handler = async (event, context) => {
  const schemas = await getSchemas();

  for (const schema of schemas) {
    if (await validateEvent(event, schema)) {
      return;
    }
  }

  await snsClient.send(
    new PublishCommand({
      TopicArn: process.env.SNS_TOPIC_ARN,
      Message: `The following payload is non-compliant:\n\n${JSON.stringify(
        event,
        null,
        2
      )}`,
    })
  );
};

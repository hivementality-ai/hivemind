import { z } from "zod";

/**
 * Convert a JSON Schema properties object into a Zod raw shape
 * suitable for the Agent SDK tool() helper.
 *
 * Handles: string (with enum), number, integer, boolean, array, object.
 * Marks optional fields based on the `required` array.
 * Adds .describe() from JSON Schema descriptions.
 */
export function jsonSchemaToZod(schema) {
  const properties = schema.properties || {};
  const required = new Set(schema.required || []);
  const shape = {};

  for (const [key, prop] of Object.entries(properties)) {
    let field = convertProperty(prop);

    if (prop.description) {
      field = field.describe(prop.description);
    }

    if (!required.has(key)) {
      field = field.optional();
    }

    shape[key] = field;
  }

  return shape;
}

function convertProperty(prop) {
  const type = prop.type;

  if (prop.enum && Array.isArray(prop.enum)) {
    if (prop.enum.length === 1) {
      return z.literal(prop.enum[0]);
    }
    return z.enum(prop.enum);
  }

  switch (type) {
    case "string":
      return z.string();

    case "number":
    case "integer":
      return z.number();

    case "boolean":
      return z.boolean();

    case "array": {
      const items = prop.items ? convertProperty(prop.items) : z.any();
      return z.array(items);
    }

    case "object": {
      if (prop.properties) {
        const nestedShape = jsonSchemaToZod(prop);
        return z.object(nestedShape);
      }
      return z.record(z.any());
    }

    default:
      return z.any();
  }
}

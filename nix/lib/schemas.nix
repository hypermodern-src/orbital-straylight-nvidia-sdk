# nix/lib/schemas.nix — Version Validation Schemas
#
# Defines the structure and validation rules for all version definitions
# in the NVIDIA SDK. Ensures consistency and catches errors at eval time.

{ lib }:

let
  # Schema for CUDA toolkit versions
  cudaSchema = {
    fields = {
      version = {
        type = "string";
        required = true;
        pattern = "^13\\.[0-9]+";
      };
      driver = {
        type = "string";
        required = true;
        pattern = "^[0-9]+\\.[0-9]+";
      };
      url = {
        type = "string";
        required = true;
      };
      hash = {
        type = "string";
        required = true;
        pattern = "^sha256-";
      };
    };
    validate =
      data:
      assert lib.assertMsg (lib.strings.hasPrefix "13." data.version)
        "CUDA version must be 13.x, got: ${data.version}";
      true;
  };

  # Schema for redistributable packages (cuDNN, TensorRT, etc.)
  redistSchema = {
    fields = {
      version = {
        type = "string";
        required = true;
      };
      urls = {
        type = "attrs";
        required = true;
        fields = {
          mirror = {
            type = "string";
            required = true;
          };
          upstream = {
            type = "string";
            required = false;
          };
        };
      };
      hash = {
        type = "string";
        required = true;
        pattern = "^sha256-";
      };
    };
    validate = _data: true;
  };

  # Schema for NGC containers
  ngcContainerSchema = {
    fields = {
      version = {
        type = "string";
        required = true;
      };
      ref = {
        type = "string";
        required = true;
        pattern = "^nvcr\\.io/";
      };
      hash = {
        type = "string";
        required = true;
        pattern = "^sha256-";
      };
    };
    validate =
      data:
      assert lib.assertMsg (lib.strings.hasPrefix "nvcr.io/" data.ref)
        "NGC container ref must start with nvcr.io/, got: ${data.ref}";
      true;
  };

  # Schema for driver versions
  driverSchema = {
    fields = {
      version = {
        type = "string";
        required = true;
        pattern = "^[0-9]+\\.[0-9]+";
      };
      url = {
        type = "string";
        required = true;
      };
      hash = {
        type = "string";
        required = true;
        pattern = "^sha256-";
      };
    };
    validate =
      data:
      assert lib.assertMsg (
        !lib.strings.hasPrefix "sha256-AAAAAAAA" data.hash
      ) "Driver hash appears to be a placeholder: ${data.hash}";
      true;
  };

  # All schemas
  versionSchemas = {
    inherit
      cudaSchema
      redistSchema
      ngcContainerSchema
      driverSchema
      ;
    cudnn = redistSchema;
    tensorrt = redistSchema;
    cutensor = redistSchema;
    nccl = redistSchema;
    cutlass = {
      fields = {
        version = {
          type = "string";
          required = true;
        };
        url = {
          type = "string";
          required = true;
        };
        hash = {
          type = "string";
          required = true;
          pattern = "^sha256-";
        };
      };
      validate = _data: true;
    };
  };

in
{
  inherit versionSchemas;

  # Helper to get schema for a package type
  getSchema = type: versionSchemas.${type} or null;

  # Validate a version definition against its schema
  validateVersion =
    type: data:
    let
      schema = getSchema type;
    in
    if schema == null then
      {
        valid = false;
        errors = [ "Unknown type: ${type}" ];
      }
    else
      let
        fieldErrors = lib.concatMap (
          field:
          let
            fieldDef = schema.fields.${field};
            value = data.${field} or null;
          in
          if fieldDef.required && value == null then
            [ "${field}: required field missing" ]
          else if value != null && fieldDef ? pattern && !(builtins.match fieldDef.pattern value) then
            [ "${field}: value '${value}' doesn't match pattern '${fieldDef.pattern}'" ]
          else
            [ ]
        ) (lib.attrNames schema.fields);

        validationResult =
          if schema ? validate && !(schema.validate data) then [ "Custom validation failed" ] else [ ];

        allErrors = fieldErrors ++ validationResult;
      in
      if allErrors == [ ] then
        {
          valid = true;
          errors = [ ];
        }
      else
        {
          valid = false;
          errors = allErrors;
        };
}

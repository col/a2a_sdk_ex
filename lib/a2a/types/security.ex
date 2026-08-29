defmodule A2A.Types.StringList do
  @moduledoc "A list of strings (proto `StringList`; used as OAuth-scope map values)."
  alias A2A.Types.Field

  @type t :: %__MODULE__{list: [String.t()]}
  defstruct list: []

  @doc false
  def __a2a_proto_name__, do: "StringList"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [Field.new(name: :list, proto_name: "list", number: 1, type: :string, cardinality: :repeated)]
  end
end

defmodule A2A.Types.SecurityRequirement do
  @moduledoc "A map of security-scheme name to the required scopes."
  alias A2A.Types.{Field, StringList}

  @type t :: %__MODULE__{schemes: %{optional(String.t()) => StringList.t()}}
  defstruct schemes: %{}

  @doc false
  def __a2a_proto_name__, do: "SecurityRequirement"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :schemes,
        proto_name: "schemes",
        number: 1,
        type: {:map, :string, {:message, StringList}}
      )
    ]
  end
end

defmodule A2A.Types.AuthorizationCodeOAuthFlow do
  @moduledoc "OAuth 2.0 Authorization Code flow configuration."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          authorization_url: String.t() | nil,
          token_url: String.t() | nil,
          refresh_url: String.t() | nil,
          scopes: %{optional(String.t()) => String.t()},
          pkce_required: boolean() | nil
        }
  defstruct [:authorization_url, :token_url, :refresh_url, :pkce_required, scopes: %{}]

  @doc false
  def __a2a_proto_name__, do: "AuthorizationCodeOAuthFlow"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :authorization_url,
        proto_name: "authorization_url",
        number: 1,
        type: :string
      ),
      Field.new(name: :token_url, proto_name: "token_url", number: 2, type: :string),
      Field.new(name: :refresh_url, proto_name: "refresh_url", number: 3, type: :string),
      Field.new(name: :scopes, proto_name: "scopes", number: 4, type: {:map, :string, :string}),
      Field.new(name: :pkce_required, proto_name: "pkce_required", number: 5, type: :bool)
    ]
  end
end

defmodule A2A.Types.ClientCredentialsOAuthFlow do
  @moduledoc "OAuth 2.0 Client Credentials flow configuration."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          token_url: String.t() | nil,
          refresh_url: String.t() | nil,
          scopes: %{optional(String.t()) => String.t()}
        }
  defstruct [:token_url, :refresh_url, scopes: %{}]

  @doc false
  def __a2a_proto_name__, do: "ClientCredentialsOAuthFlow"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :token_url, proto_name: "token_url", number: 1, type: :string),
      Field.new(name: :refresh_url, proto_name: "refresh_url", number: 2, type: :string),
      Field.new(name: :scopes, proto_name: "scopes", number: 3, type: {:map, :string, :string})
    ]
  end
end

defmodule A2A.Types.ImplicitOAuthFlow do
  @moduledoc "OAuth 2.0 Implicit flow configuration (deprecated in the spec, modeled for completeness)."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          authorization_url: String.t() | nil,
          refresh_url: String.t() | nil,
          scopes: %{optional(String.t()) => String.t()}
        }
  defstruct [:authorization_url, :refresh_url, scopes: %{}]

  @doc false
  def __a2a_proto_name__, do: "ImplicitOAuthFlow"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :authorization_url,
        proto_name: "authorization_url",
        number: 1,
        type: :string
      ),
      Field.new(name: :refresh_url, proto_name: "refresh_url", number: 2, type: :string),
      Field.new(name: :scopes, proto_name: "scopes", number: 3, type: {:map, :string, :string})
    ]
  end
end

defmodule A2A.Types.PasswordOAuthFlow do
  @moduledoc "OAuth 2.0 Password flow configuration (deprecated in the spec, modeled for completeness)."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          token_url: String.t() | nil,
          refresh_url: String.t() | nil,
          scopes: %{optional(String.t()) => String.t()}
        }
  defstruct [:token_url, :refresh_url, scopes: %{}]

  @doc false
  def __a2a_proto_name__, do: "PasswordOAuthFlow"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :token_url, proto_name: "token_url", number: 1, type: :string),
      Field.new(name: :refresh_url, proto_name: "refresh_url", number: 2, type: :string),
      Field.new(name: :scopes, proto_name: "scopes", number: 3, type: {:map, :string, :string})
    ]
  end
end

defmodule A2A.Types.DeviceCodeOAuthFlow do
  @moduledoc "OAuth 2.0 Device Code flow configuration (RFC 8628)."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          device_authorization_url: String.t() | nil,
          token_url: String.t() | nil,
          refresh_url: String.t() | nil,
          scopes: %{optional(String.t()) => String.t()}
        }
  defstruct [:device_authorization_url, :token_url, :refresh_url, scopes: %{}]

  @doc false
  def __a2a_proto_name__, do: "DeviceCodeOAuthFlow"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :device_authorization_url,
        proto_name: "device_authorization_url",
        number: 1,
        type: :string
      ),
      Field.new(name: :token_url, proto_name: "token_url", number: 2, type: :string),
      Field.new(name: :refresh_url, proto_name: "refresh_url", number: 3, type: :string),
      Field.new(name: :scopes, proto_name: "scopes", number: 4, type: {:map, :string, :string})
    ]
  end
end

defmodule A2A.Types.OAuthFlows do
  @moduledoc """
  The supported OAuth 2.0 flows: a tagged union over
  `authorization_code | client_credentials | implicit | password | device_code`.
  Match on `:kind`.
  """
  alias A2A.Types.{
    AuthorizationCodeOAuthFlow,
    ClientCredentialsOAuthFlow,
    DeviceCodeOAuthFlow,
    Field,
    ImplicitOAuthFlow,
    PasswordOAuthFlow
  }

  @type kind :: :authorization_code | :client_credentials | :implicit | :password | :device_code
  @type t :: %__MODULE__{
          kind: kind | nil,
          authorization_code: AuthorizationCodeOAuthFlow.t() | nil,
          client_credentials: ClientCredentialsOAuthFlow.t() | nil,
          implicit: ImplicitOAuthFlow.t() | nil,
          password: PasswordOAuthFlow.t() | nil,
          device_code: DeviceCodeOAuthFlow.t() | nil
        }
  defstruct [:kind, :authorization_code, :client_credentials, :implicit, :password, :device_code]

  @spec authorization_code(AuthorizationCodeOAuthFlow.t()) :: t
  def authorization_code(v), do: %__MODULE__{kind: :authorization_code, authorization_code: v}

  @spec client_credentials(ClientCredentialsOAuthFlow.t()) :: t
  def client_credentials(v), do: %__MODULE__{kind: :client_credentials, client_credentials: v}

  @spec implicit(ImplicitOAuthFlow.t()) :: t
  def implicit(v), do: %__MODULE__{kind: :implicit, implicit: v}

  @spec password(PasswordOAuthFlow.t()) :: t
  def password(v), do: %__MODULE__{kind: :password, password: v}

  @spec device_code(DeviceCodeOAuthFlow.t()) :: t
  def device_code(v), do: %__MODULE__{kind: :device_code, device_code: v}

  @doc false
  def __a2a_proto_name__, do: "OAuthFlows"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :authorization_code,
        proto_name: "authorization_code",
        number: 1,
        type: {:message, AuthorizationCodeOAuthFlow},
        presence: :explicit,
        oneof: {:flow, :authorization_code}
      ),
      Field.new(
        name: :client_credentials,
        proto_name: "client_credentials",
        number: 2,
        type: {:message, ClientCredentialsOAuthFlow},
        presence: :explicit,
        oneof: {:flow, :client_credentials}
      ),
      Field.new(
        name: :implicit,
        proto_name: "implicit",
        number: 3,
        type: {:message, ImplicitOAuthFlow},
        presence: :explicit,
        oneof: {:flow, :implicit}
      ),
      Field.new(
        name: :password,
        proto_name: "password",
        number: 4,
        type: {:message, PasswordOAuthFlow},
        presence: :explicit,
        oneof: {:flow, :password}
      ),
      Field.new(
        name: :device_code,
        proto_name: "device_code",
        number: 5,
        type: {:message, DeviceCodeOAuthFlow},
        presence: :explicit,
        oneof: {:flow, :device_code}
      )
    ]
  end
end

defmodule A2A.Types.APIKeySecurityScheme do
  @moduledoc "API-key security scheme."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          description: String.t() | nil,
          location: String.t() | nil,
          name: String.t() | nil
        }
  defstruct [:description, :location, :name]

  @doc false
  def __a2a_proto_name__, do: "APIKeySecurityScheme"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :description, proto_name: "description", number: 1, type: :string),
      Field.new(name: :location, proto_name: "location", number: 2, type: :string),
      Field.new(name: :name, proto_name: "name", number: 3, type: :string)
    ]
  end
end

defmodule A2A.Types.HTTPAuthSecurityScheme do
  @moduledoc "HTTP-authentication security scheme."
  alias A2A.Types.Field

  @type t :: %__MODULE__{
          description: String.t() | nil,
          scheme: String.t() | nil,
          bearer_format: String.t() | nil
        }
  defstruct [:description, :scheme, :bearer_format]

  @doc false
  def __a2a_proto_name__, do: "HTTPAuthSecurityScheme"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :description, proto_name: "description", number: 1, type: :string),
      Field.new(name: :scheme, proto_name: "scheme", number: 2, type: :string),
      Field.new(name: :bearer_format, proto_name: "bearer_format", number: 3, type: :string)
    ]
  end
end

defmodule A2A.Types.OAuth2SecurityScheme do
  @moduledoc "OAuth 2.0 security scheme."
  alias A2A.Types.{Field, OAuthFlows}

  @type t :: %__MODULE__{
          description: String.t() | nil,
          flows: OAuthFlows.t() | nil,
          oauth2_metadata_url: String.t() | nil
        }
  defstruct [:description, :flows, :oauth2_metadata_url]

  @doc false
  def __a2a_proto_name__, do: "OAuth2SecurityScheme"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :description, proto_name: "description", number: 1, type: :string),
      Field.new(name: :flows, proto_name: "flows", number: 2, type: {:message, OAuthFlows}),
      Field.new(
        name: :oauth2_metadata_url,
        proto_name: "oauth2_metadata_url",
        number: 3,
        type: :string
      )
    ]
  end
end

defmodule A2A.Types.OpenIdConnectSecurityScheme do
  @moduledoc "OpenID Connect security scheme."
  alias A2A.Types.Field

  @type t :: %__MODULE__{description: String.t() | nil, open_id_connect_url: String.t() | nil}
  defstruct [:description, :open_id_connect_url]

  @doc false
  def __a2a_proto_name__, do: "OpenIdConnectSecurityScheme"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :description, proto_name: "description", number: 1, type: :string),
      Field.new(
        name: :open_id_connect_url,
        proto_name: "open_id_connect_url",
        number: 2,
        type: :string
      )
    ]
  end
end

defmodule A2A.Types.MutualTlsSecurityScheme do
  @moduledoc "Mutual-TLS security scheme."
  alias A2A.Types.Field

  @type t :: %__MODULE__{description: String.t() | nil}
  defstruct [:description]

  @doc false
  def __a2a_proto_name__, do: "MutualTlsSecurityScheme"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [Field.new(name: :description, proto_name: "description", number: 1, type: :string)]
  end
end

defmodule A2A.Types.AuthenticationInfo do
  @moduledoc "Authentication info for push-notification delivery."
  alias A2A.Types.Field

  @type t :: %__MODULE__{scheme: String.t() | nil, credentials: String.t() | nil}
  defstruct [:scheme, :credentials]

  @doc false
  def __a2a_proto_name__, do: "AuthenticationInfo"

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(name: :scheme, proto_name: "scheme", number: 1, type: :string),
      Field.new(name: :credentials, proto_name: "credentials", number: 2, type: :string)
    ]
  end
end

defmodule A2A.Types.SecurityScheme do
  @moduledoc """
  A security scheme: a tagged union over
  `api_key | http_auth | oauth2 | open_id_connect | mtls`. Match on `:kind`.
  Struct keys are the short idiomatic forms; proto field names (and thus the
  proto3-JSON keys, e.g. `apiKeySecurityScheme`) are the verbose spec forms.
  """
  alias A2A.Types.{
    APIKeySecurityScheme,
    Field,
    HTTPAuthSecurityScheme,
    MutualTlsSecurityScheme,
    OAuth2SecurityScheme,
    OpenIdConnectSecurityScheme
  }

  @type kind :: :api_key | :http_auth | :oauth2 | :open_id_connect | :mtls
  @type t :: %__MODULE__{
          kind: kind | nil,
          api_key: APIKeySecurityScheme.t() | nil,
          http_auth: HTTPAuthSecurityScheme.t() | nil,
          oauth2: OAuth2SecurityScheme.t() | nil,
          open_id_connect: OpenIdConnectSecurityScheme.t() | nil,
          mtls: MutualTlsSecurityScheme.t() | nil
        }
  defstruct [:kind, :api_key, :http_auth, :oauth2, :open_id_connect, :mtls]

  @spec api_key(APIKeySecurityScheme.t()) :: t
  def api_key(v), do: %__MODULE__{kind: :api_key, api_key: v}

  @spec http_auth(HTTPAuthSecurityScheme.t()) :: t
  def http_auth(v), do: %__MODULE__{kind: :http_auth, http_auth: v}

  @spec oauth2(OAuth2SecurityScheme.t()) :: t
  def oauth2(v), do: %__MODULE__{kind: :oauth2, oauth2: v}

  @spec open_id_connect(OpenIdConnectSecurityScheme.t()) :: t
  def open_id_connect(v), do: %__MODULE__{kind: :open_id_connect, open_id_connect: v}

  @spec mtls(MutualTlsSecurityScheme.t()) :: t
  def mtls(v), do: %__MODULE__{kind: :mtls, mtls: v}

  @doc false
  def __a2a_proto_name__, do: "SecurityScheme"
  @doc false
  def __a2a_discriminator__, do: :kind

  @doc false
  @spec __a2a_fields__() :: [Field.t()]
  def __a2a_fields__ do
    [
      Field.new(
        name: :api_key,
        proto_name: "api_key_security_scheme",
        number: 1,
        type: {:message, APIKeySecurityScheme},
        presence: :explicit,
        oneof: {:scheme, :api_key}
      ),
      Field.new(
        name: :http_auth,
        proto_name: "http_auth_security_scheme",
        number: 2,
        type: {:message, HTTPAuthSecurityScheme},
        presence: :explicit,
        oneof: {:scheme, :http_auth}
      ),
      Field.new(
        name: :oauth2,
        proto_name: "oauth2_security_scheme",
        number: 3,
        type: {:message, OAuth2SecurityScheme},
        presence: :explicit,
        oneof: {:scheme, :oauth2}
      ),
      Field.new(
        name: :open_id_connect,
        proto_name: "open_id_connect_security_scheme",
        number: 4,
        type: {:message, OpenIdConnectSecurityScheme},
        presence: :explicit,
        oneof: {:scheme, :open_id_connect}
      ),
      Field.new(
        name: :mtls,
        proto_name: "mtls_security_scheme",
        number: 5,
        type: {:message, MutualTlsSecurityScheme},
        presence: :explicit,
        oneof: {:scheme, :mtls}
      )
    ]
  end
end

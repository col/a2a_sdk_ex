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

defmodule Exdock.ImageReference do
  @moduledoc "Application facade for the shared image-reference parser."

  alias Exdock.Protocol.ImageReference, as: Parser

  defdelegate infer_urls_from_tag(reference), to: Parser
  defdelegate registry_url(reference), to: Parser
  defdelegate repository_url(reference), to: Parser
  defdelegate categorize_registry(reference), to: Parser
  defdelegate truncate_tag(reference), to: Parser
  defdelegate normalize_tag(reference), to: Parser
  defdelegate image_id?(reference), to: Parser
end

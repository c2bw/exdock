defmodule Exdock.Timezone do
  @doc """
  Retrieve the user timezone from the application environment.

  Defaults to "Etc/UTC".
  """
  def user_timezone() do
    case Application.fetch_env(:exdock, :timezone) do
      {:ok, tz} -> tz
      :error -> "Etc/UTC"
    end
  end
end

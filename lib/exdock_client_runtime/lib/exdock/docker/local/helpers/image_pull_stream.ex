defmodule Exdock.Docker.Local.Helpers.ImagePullStream do
  @moduledoc """
  Pure state reducer for Docker's newline-delimited image-pull stream.

  Transport chunks may split or combine JSON records. This module owns that
  buffering and reduces decoded records to progress events and a final result.
  """

  alias Exdock.Docker.Error

  defstruct status_code: nil,
            status_reason: nil,
            docker_error: nil,
            stream_error: nil,
            buffer: ""

  @type event :: {:progress, String.t(), number(), number()}

  @type t :: %__MODULE__{
          status_code: integer() | nil,
          status_reason: term(),
          docker_error: term(),
          stream_error: term(),
          buffer: binary()
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec consume(t(), term()) :: {t(), [event()]}
  def consume(%__MODULE__{} = state, chunk) when is_binary(chunk) do
    [tail | complete_records] =
      state.buffer
      |> Kernel.<>(chunk)
      |> :binary.split("\n", [:global])
      |> Enum.reverse()

    {state, reversed_events} =
      complete_records
      |> Enum.reverse()
      |> Enum.reduce({state, []}, &consume_record_reversed/2)

    consume_possible_record(%{state | buffer: tail}, Enum.reverse(reversed_events))
  end

  def consume(%__MODULE__{} = state, {:status, status_code, reason})
      when is_integer(status_code),
      do: {%{state | status_code: status_code, status_reason: reason}, []}

  def consume(%__MODULE__{} = state, %{"errorDetail" => %{"message" => message}}),
    do: {set_docker_error(state, message), []}

  def consume(%__MODULE__{} = state, %{"error" => message}),
    do: {set_docker_error(state, message), []}

  def consume(%__MODULE__{} = state, %{"message" => message}) do
    state = if failed_status?(state.status_code), do: set_docker_error(state, message), else: state
    {state, []}
  end

  def consume(
        %__MODULE__{} = state,
        %{
          "status" => action,
          "progressDetail" => %{"current" => current, "total" => total},
          "id" => _layer_id
        }
      )
      when action in ["Downloading", "Extracting"] do
    {state, [{:progress, action, current, total}]}
  end

  def consume(%__MODULE__{} = state, _body), do: {state, []}

  @spec finish(t()) :: {t(), [event()], :ok | {:error, Error.t()}}
  def finish(%__MODULE__{buffer: buffer} = state) do
    state = %{state | buffer: ""}

    {state, events} =
      if blank_record?(buffer) do
        {state, []}
      else
        consume_complete_record(buffer, state)
      end

    {state, events, completion_result(state)}
  end

  defp consume_record_reversed(record, {state, reversed_events}) do
    if blank_record?(record) do
      {state, reversed_events}
    else
      {state, new_events} = consume_complete_record(record, state)
      {state, Enum.reverse(new_events, reversed_events)}
    end
  end

  defp consume_complete_record(record, state) do
    case decode_record(record) do
      {:ok, decoded} -> consume(state, decoded)
      :error -> {set_stream_error(state, record), []}
    end
  end

  defp consume_possible_record(%{buffer: buffer} = state, events) do
    case decode_record(buffer) do
      {:ok, decoded} ->
        {state, new_events} = consume(%{state | buffer: ""}, decoded)
        {state, Enum.reverse(new_events, Enum.reverse(events))}

      :error ->
        {state, events}
    end
  end

  defp decode_record(record) when is_binary(record) do
    case JSON.decode(record) do
      {:ok, %{} = decoded} -> {:ok, decoded}
      _other -> :error
    end
  end

  defp blank_record?(record) when is_binary(record) do
    record
    |> :binary.bin_to_list()
    |> Enum.all?(&(&1 in [?\s, ?\t, ?\r, ?\n]))
  end

  defp set_docker_error(state, cause), do: %{state | docker_error: cause}

  defp completion_result(%{docker_error: cause, status_code: status}) when not is_nil(cause) do
    Error.new(:image_pull, {:docker_stream, cause},
      status: status,
      message: docker_error_message(cause)
    )
    |> then(&{:error, &1})
  end

  defp completion_result(%{status_code: status, status_reason: reason})
       when is_integer(status) and status not in 200..299,
       do:
         {:error,
          Error.new(:image_pull, {:http_status, reason},
            status: status,
            message: "Docker pull failed with HTTP status #{status}"
          )}

  defp completion_result(%{stream_error: cause}) when not is_nil(cause),
    do: {:error, Error.new({:image_pull, :stream_decode}, cause, message: "Docker pull stream contained malformed JSON")}

  defp completion_result(%{status_code: status}) when status in 200..299, do: :ok

  defp completion_result(%{status_code: nil}),
    do: {:error, Error.new(:image_pull, :missing_http_status, message: "Docker pull ended without an HTTP status")}

  defp set_stream_error(%{stream_error: nil} = state, record),
    do: %{state | stream_error: {:malformed_json, record}}

  defp set_stream_error(state, _record), do: state

  defp failed_status?(status), do: is_integer(status) and status not in 200..299

  defp docker_error_message(message) when is_binary(message), do: message
  defp docker_error_message(_cause), do: "Docker image pull failed"
end

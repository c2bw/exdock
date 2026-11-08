defmodule Exdock.Protocol.EnvelopeTest do
  use ExUnit.Case, async: true

  alias Exdock.Protocol.{Contract, Envelope}

  test "decodes framing before delegating payload validation" do
    frame = Contract.encode_term_frame(:error, :failure)

    assert {:decoded, :failure} =
             Envelope.decode(frame, fn :error, payload ->
               Envelope.decode_term(payload, &{:ok, {:decoded, &1}})
             end)
  end

  test "preserves contract errors and normalizes invalid inputs" do
    assert {:error, :version_too_old} = Envelope.decode(<<3, 1>>, fn _, _ -> flunk() end)
    assert {:error, :malformed_message} = Envelope.decode(:not_a_frame, fn _, _ -> flunk() end)

    assert {:error, :malformed_message} =
             Envelope.decode_term(<<1, 2, 3>>, &{:ok, &1})
  end
end

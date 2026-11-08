defmodule Exdock.Server.Connection.SelfCertTest do
  use ExUnit.Case, async: true

  alias Exdock.Server.Connection.SelfCert

  test "builds a host-verifiable certificate from deterministic profile inputs" do
    {certificate, _private_key} =
      SelfCert.certificate_and_key(1024, "Exdock Test", ["localhost"],
        clock: fn -> ~D[2026-08-01] end,
        serial_number: 42
      )

    decoded = :public_key.pkix_decode_cert(certificate, :otp)

    assert :public_key.pkix_verify_hostname(decoded, [{:dns_id, ~c"localhost"}])
    refute :public_key.pkix_verify_hostname(decoded, [{:dns_id, ~c"other.example"}])
  end
end

defmodule Exdock.Server.Connection.SelfCert.Profile do
  @moduledoc "Pure X.509 profile construction for Exdock's ephemeral certificate."

  require Record

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :signature_algorithm,
    :SignatureAlgorithm,
    Record.extract(:SignatureAlgorithm, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :validity,
    :Validity,
    Record.extract(:Validity, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :otp_subject_public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :public_key_algorithm,
    :PublicKeyAlgorithm,
    Record.extract(:PublicKeyAlgorithm, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :extension,
    :Extension,
    Record.extract(:Extension, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :basic_constraints,
    :BasicConstraints,
    Record.extract(:BasicConstraints, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  Record.defrecordp(
    :attr,
    :AttributeTypeAndValue,
    Record.extract(:AttributeTypeAndValue, from_lib: "public_key/include/OTP-PUB-KEY.hrl")
  )

  @rsa_encryption {1, 2, 840, 113_549, 1, 1, 1}
  @sha256_with_rsa {1, 2, 840, 113_549, 1, 1, 11}
  @basic_constraints {2, 5, 29, 19}
  @key_usage {2, 5, 29, 15}
  @extended_key_usage {2, 5, 29, 37}
  @subject_key_identifier {2, 5, 29, 14}
  @subject_alternative_name {2, 5, 29, 17}
  @organization_name {2, 5, 4, 10}
  @common_name {2, 5, 4, 3}
  @server_auth {1, 3, 6, 1, 5, 5, 7, 3, 1}
  @client_auth {1, 3, 6, 1, 5, 5, 7, 3, 2}

  @spec build(term(), String.t(), [String.t()], Date.t(), pos_integer()) :: tuple()
  def build(public_key, common_name, hostnames, %Date{} = today, serial)
      when is_binary(common_name) and is_list(hostnames) and is_integer(serial) and serial > 0 do
    otp_tbs_certificate(
      version: :v3,
      serialNumber: serial,
      signature: signature_algorithm(algorithm: @sha256_with_rsa, parameters: :asn1_NOVALUE),
      issuer: rdn(common_name),
      validity: validity_period(today),
      subject: rdn(common_name),
      subjectPublicKeyInfo:
        otp_subject_public_key_info(
          algorithm: public_key_algorithm(algorithm: @rsa_encryption, parameters: :asn1_NOVALUE),
          subjectPublicKey: public_key
        ),
      extensions: extensions(public_key, hostnames)
    )
  end

  defp validity_period(today) do
    not_before = utc_date(today)
    not_after = today |> Date.add(365 * 5) |> utc_date()
    validity(notBefore: {:utcTime, ~c"#{not_before}000000Z"}, notAfter: {:utcTime, ~c"#{not_after}000000Z"})
  end

  defp utc_date(date), do: date |> Date.to_iso8601(:basic) |> String.slice(2, 6)

  defp rdn(common_name) do
    {:rdnSequence,
     [
       [attr(type: @organization_name, value: {:utf8String, "Phoenix Framework"})],
       [attr(type: @common_name, value: {:utf8String, common_name})]
     ]}
  end

  defp extensions(public_key, hostnames) do
    [
      extension(
        extnID: @basic_constraints,
        critical: true,
        extnValue: basic_constraints(cA: false)
      ),
      extension(extnID: @key_usage, critical: true, extnValue: [:digitalSignature, :keyEncipherment]),
      extension(extnID: @extended_key_usage, critical: false, extnValue: [@server_auth, @client_auth]),
      extension(extnID: @subject_key_identifier, critical: false, extnValue: key_identifier(public_key)),
      extension(
        extnID: @subject_alternative_name,
        critical: false,
        extnValue: Enum.map(hostnames, &{:dNSName, String.to_charlist(&1)})
      )
    ]
  end

  defp key_identifier(public_key),
    do: :crypto.hash(:sha, :public_key.der_encode(:RSAPublicKey, public_key))
end

{
  "subject": {"commonName": {{ toJson .Insecure.CR.Subject.CommonName }}},
  "sans": {{ toJson .SANs }},
  "keyUsage": ["digitalSignature", "keyAgreement"],
  "extKeyUsage": ["clientAuth"]
}
{
  "subject": {{ toJson .Subject }},
  "sans": {{ toJson .SANs }},
  "keyUsage": ["digitalSignature", "keyEncipherment", "keyAgreement"],
  "extKeyUsage": ["serverAuth"]
}
{
    "subject": {
        "country": "IL",
        "organization": "MyOrganization",
        "commonName": "{{ .Subject.CommonName }}"
    },
  "sans": {{ toJson .SANs }}
}
---
layout: post
title: "Generating self-signed certificates with OpenSSL" 
---

I occasionally need to generate self-signed certificates using OpenSSL and convert them into a format that Windows can understand. I have to look this up every time, so I'm putting it here in order that I can look in a known place!

```sh
$ openssl req -x509 -newkey rsa:2048 -subj '/CN=whatever' -keyout key.pem -nodes -out cert.cer -days 365
$ openssl pkcs12 -export -password pass:'' -in cert.cer -inkey key.pem -out certificate.pfx
```

Windows will happily then install the `pfx` file.

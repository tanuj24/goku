<p align="center"><img src="assets/goku-logo.svg" alt="Goku: a terminal prompt surfing a golden cloud" width="560"></p>

<p align="center"><strong>Goku — your local AWS cloud.</strong> <em>Formerly Mimir.</em></p>

<p align="center">
S3, Lambda, DynamoDB, RDS, Step Functions, API Gateway, Glue and 70+ AWS services<br>
running on your machine — with a web console for 60 services. Free. No AWS account.
</p>

---

**Mimir is now Goku, everywhere.** From 4.1 every name is Goku: the image `tanujsoni027/goku`, the `goku`
container and command, `GOKU_*` settings, `/_goku` paths and `goku.local` host names. Existing installs move over
automatically (`goku update`, or **Update now** in the console) and the old names keep working for now, so start
using the goku names. See [old and new names](https://tanuj24.github.io/goku/install.html#names).

## Install

macOS and Linux:

```bash
curl -fsSL https://tanuj24.github.io/goku/install.sh | sh
goku start
```

Windows (PowerShell):

```powershell
irm https://tanuj24.github.io/goku/install.ps1 | iex
goku start
```

Or run it with Docker directly — see **[all installation options](https://tanuj24.github.io/goku/install.html)**.

- 🌐 **Website:** https://tanuj24.github.io/goku/
- 🐳 **Docker Hub:** https://hub.docker.com/r/tanujsoni027/goku
- 🐛 **Bug reports & feature requests:** [Issues](https://github.com/tanuj24/goku/issues)

Goku is an independent project and is not affiliated with or endorsed by Amazon Web Services.

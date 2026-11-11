# Security

FotoAsist GC works locally: it reads photographs you choose, writes its catalog, cache, results and logs to its own folders, and makes one kind of network request, the update check (a read of this repository's latest release, when you ask for it or when the About window checks).

If you find a security problem, for example a file that makes the decoder crash in an exploitable way or a path that lets the application write outside its folders, please report it privately through GitHub: the repository's **Security** tab → **Report a vulnerability**. Do not open a public issue for it.

The project is maintained occasionally, so a fix can take time. Supported version: the latest release.

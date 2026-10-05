import Foundation

/// Oracle's real detached signature of `mysql-8.4.11-macos15-arm64.tar.gz` (167 977 240 bytes,
/// SHA-256 `b96e00493bc3499b9ffd7f08d65c5d64933af0383a8287d9873b64f94c2d6009`).
enum OracleSignatureFixture {
    static let armored = Data(
        """
        -----BEGIN PGP SIGNATURE-----

        iQIzBAABCAAdFiEEvKQ0F8O0hd0SjsbUt7O3iKjTeFwFAmpFWfIACgkQt7O3iKjT
        eFxvig//bZ/vMiLWucD8sBkv8NQL/7SnMraGtb83wHy9kZvwby1RkVoE8DEW3o45
        bLbidtda9PtPVBC129Bc5wK6sIh5WDtUjZzEcXF4VbEjTQeiZAEL5mGQAA11gPzM
        kqYMNlc/PEP3unMtLR/CPuozi/6zhU1ngiUvTd157Dr+1DY4tQY6/fWG4qW74XdD
        DlmH76MzTvUmshaI2ZAvWCGnIOwBK2/x5bzo/4ctsgYUrFKqxZ8AfG6nzV7Yk6jk
        G8OcJtSfqDEoA5ncAnND+r7g0Je8ri6eZuxyrAmQkEp5c3Z8sRtnrFykNZ0sZPWF
        rfKJJgw5a9NISUES4XgS6FtYAHFgXxLKFDguwXuOvOXi7RlAf9mhWJR73FgWG3Jz
        CDURymP0NVhWyjC+0SDxFjf0q41H7XX8WFKge5eP16ZJ64YHPsjqc9OGjMhFgeiU
        tKdpNLa0MJLqPIMjslpZrwbFAqLQLVtDmXFY/jE0hfWUrHzTWI5a0byIrYHmE8VQ
        JM3OYygRBELRzs1PW3IT/mpVmu3LDHBGWnU3bGPURHNDvEECOIXPKQMZwyjkizPt
        /JnYopX1Ih5fxV3vyhwIbne0r1HsEQgoEERoCgu0lZ42sZpEKwu4K1b6zw38Lve8
        0ExpZiNbR/7YFevqdax544ao5GOGZRj22sGqY2AGalJl2rtVRg0=
        =HAvA
        -----END PGP SIGNATURE-----

        """.utf8)

    /// SHA-256 of the archive bytes followed by the v4 trailer, computed once from the real archive.
    static let digestHex = "6f8a474525237aa7ced90bc0038ca31e539b801472ffd88aecdb67bd492fb328"

    /// The length of the signed header (version through the hashed subpackets).
    static let signedHeaderLength = 35
}

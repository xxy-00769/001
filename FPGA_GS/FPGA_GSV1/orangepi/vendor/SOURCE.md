# Frozen upstream copies

`protocol.py` is an unchanged byte-for-byte copy of project `tools/m3/protocol.py`.
SHA256: `64BB3BE5BC1BE994E9624626BE6077CA7C5EF6E149A79AA60856BFA644AF4695`.
`M4_link_contract.md` is an unchanged reference snapshot of `docs/M4_link_contract.md`, read on 2026-10-21 Asia/Shanghai.

Do not add a new wire format here. Compare and refresh from the shared upstream after an agreed contract change. M4-01 only sends the existing GSV3 control messages and receives FRONT_RAW. FILE_TEST does not instantiate the link. SIMULATION restricts both UDP addresses to loopback.

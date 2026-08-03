# MyCenter Licensing and Attribution Record

## Scope and limits

This is an engineering inventory, not legal advice. Distribution decisions must be reviewed against the exact source and binary contents being shipped.

## MeshCentral server

The checked-out MeshCentral repository contains the full Apache License 2.0 text in [`LICENSE`](../LICENSE), declares Apache 2.0 in [`README.md`](../README.md), and declares `Apache-2.0` in [`package.json`](../package.json). MyCenter modifications retain that license file, existing copyright headers, and the bundled third-party notices.

Practical fork requirements derived from the included Apache 2.0 text include:

- retain the license and applicable copyright, patent, attribution, and notice text when redistributing source or object form;
- state significant modifications in modified files or accompanying documentation;
- do not imply upstream endorsement;
- evaluate and retain third-party licenses independently;
- do not treat the license as a grant of trademark rights.

The product-facing Legal text states:

> MyCenter is based on the MeshCentral and MeshAgent open-source projects.

It links to the public upstream repositories and does not replace the bundled notices.

## MeshAgent

The separately audited upstream checkout is:

- repository: `https://github.com/Ylianst/MeshAgent.git`;
- commit: `ebff7fb7b3e0de9b13b3c7402e015f22e70fab72`;
- branch: `master` at audit time.

Its README states Apache License 2.0. The audited checkout did not contain root `LICENSE` or `NOTICE` files. That absence is a licensing-completeness risk: the README statement alone is not a substitute for verifying the license package that accompanies the exact agent source and binaries distributed in production.

MyCenter does not modify the MeshAgent source or protocol. The UI label “MyCenter Agent” is presentation-only; Legal explains that the compatible component is the original MeshAgent. Before redistributing an agent binary, retain all notices shipped with that exact binary/source package and independently review any embedded third-party components.

## Bundled third-party material

Existing third-party license and credit files include, at minimum:

- [`public/mstsc/LICENSE`](../public/mstsc/LICENSE);
- [`public/novnc/LICENSE.txt`](../public/novnc/LICENSE.txt);
- [`public/novnc/app/sounds/CREDITS`](../public/novnc/app/sounds/CREDITS);
- [`public/novnc/vendor/pako/LICENSE`](../public/novnc/vendor/pako/LICENSE);
- [`rdp/LICENSE`](../rdp/LICENSE).

The generated Terms page also contains upstream third-party disclosures. These files and disclosures must remain in source and distribution artifacts as applicable.

## MyCenter changes

MyCenter adds or changes only the server-side product presentation and deployment layer at this stage:

- product title and visible UI strings;
- original MyCenter SVG, PNG, and ICO artwork;
- green pixel-shell CSS and accessibility rules;
- local-only theme/resource policy;
- Docker/VPS deployment, backup, update, rollback, and security documentation.

It does not change the MeshAgent handshake, identity fields, binary protocol, agent/relay endpoints, authentication permission model, or original MeshAgent binary.

## Release checklist

Before each public release:

1. Confirm `LICENSE` and all listed third-party license/credit files are present and unchanged unless a reviewed dependency update requires a corresponding notice update.
2. Record the exact MeshCentral base commit, MyCenter commit, MeshAgent version/hash, and container base image digest.
3. Review new dependencies and their licenses; do not assume Apache 2.0 covers them.
4. Include a source-origin and modification notice in release documentation and the Legal/About UI.
5. Verify branding does not reuse the MeshCentral logo or imply endorsement.
6. Verify the exact agent distribution contains the license/notice material required by its upstream package.

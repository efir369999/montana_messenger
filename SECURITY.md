# Security

Montana is beta software. If you find a weakness in the protocol core, in Montana for iPhone, iPad and Mac, in Montana for
Android or in the nodes they talk to, write to contact@montana.quest rather than opening a public issue, and give us a
reasonable time to close it before publishing.

The findings the project already knows are catalogued in [`AUDIT.md`](AUDIT.md), section 6; a report that adds to one of
them is welcome and is credited to it.

In scope:

- anything that lets a third party read, alter or forge a letter, a call or a transfer record;
- anything that reveals who talks to whom, or when, to someone other than the two parties;
- anything that lets one device impersonate another identity;
- anything that makes the core's implementation differ from the specification set in `core/docs`.

Not a finding on its own:

- a dropped or redirected call or letter that a party can detect;
- rate limiting, missing headers or version disclosure on the public web site.

<!-- current-build:start -->
## The current build

The current build is 1.0 (2322), source commit `09f6bff2c957`. What each build changes for the security and the anonymity of Montana is written in its entry in [`CHANGELOG.md`](CHANGELOG.md), under **Security and anonymity**, before the build is made.
<!-- current-build:end -->
